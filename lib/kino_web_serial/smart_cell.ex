defmodule KinoWebSerial.SmartCell do
  @moduledoc """
  The **Web Serial** Smart Cell.

  Lets the user pick a serial port with the given connection options,
  send data to it and see the data sent and received. The generated
  code binds a `KinoWebSerial.Port` handle for use with the
  `KinoWebSerial` API.

  The cell is also the bridge between Elixir and the browser: the
  `SerialPort` and its streams can only live in JavaScript, so
  operations requested by the `KinoWebSerial.Port` server are forwarded
  to the browser client that opened the port, and results and received
  data are sent back. All other state lives in Elixir.
  """

  use Kino.JS, assets_path: "lib/assets/serial_cell"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Web Serial"

  alias KinoWebSerial.{Log, Options, Port, Value}

  @option_fields Map.keys(Options.defaults())

  @signals %{
    data_terminal_ready: "dataTerminalReady",
    request_to_send: "requestToSend",
    break: "break"
  }

  @status_signals %{
    "clearToSend" => :clear_to_send,
    "dataSetReady" => :data_set_ready,
    "dataCarrierDetect" => :data_carrier_detect,
    "ringIndicator" => :ring_indicator
  }

  @default_send %{"value" => "", "format" => "text", "line_ending" => "lf"}

  @impl true
  def init(attrs, ctx) do
    port_id = start_port(attrs["port_id"])

    options =
      for {field, default} <- Options.defaults(), into: %{} do
        case Options.cast(field, attrs[Atom.to_string(field)]) do
          {:ok, value} -> {field, value}
          :error -> {field, default}
        end
      end

    {:ok,
     assign(ctx,
       port_id: port_id,
       variable: Kino.SmartCell.prefixed_var_name("serial", attrs["variable"]),
       options: options,
       send: Map.merge(@default_send, attrs["send"] || %{}),
       display: if(attrs["display"] == "hex", do: "hex", else: "text"),
       port: %{status: :disconnected, usb_vendor_id: nil, usb_product_id: nil, options: nil},
       log: Log.new(),
       owner: nil,
       error: nil
     )}
  end

  defp start_port(id) do
    id = id || "serial-" <> Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

    case Port.start_link(id: id, bridge: self()) do
      {:ok, _pid} -> id
      # The id is taken, for example by a copy of this cell
      {:error, {:already_started, _pid}} -> start_port(nil)
    end
  end

  @impl true
  def handle_connect(ctx) do
    # The client holding the open port has been re-rendered and lost it
    if ctx.origin == ctx.assigns.owner, do: Port.disconnected(port(ctx))

    payload = %{
      fields: fields(ctx),
      choices:
        Map.merge(Options.choices(), %{
          formats: Value.formats(),
          line_endings: Value.line_endings()
        }),
      port: port_view(ctx),
      log: Enum.map(Log.entries(ctx.assigns.log), &entry_view/1),
      max_entries: ctx.assigns.log.max_entries
    }

    {:ok, payload, ctx}
  end

  ## Events from the UI

  @impl true
  def handle_event("update_field", %{"field" => "variable", "value" => variable}, ctx) do
    ctx =
      if Kino.SmartCell.valid_variable_name?(variable),
        do: assign(ctx, variable: variable),
        else: ctx

    broadcast_event(ctx, "fields", fields(ctx))
    {:noreply, ctx}
  end

  def handle_event("update_field", %{"field" => "display", "value" => display}, ctx) do
    ctx = if display in ["text", "hex"], do: assign(ctx, display: display), else: ctx
    broadcast_event(ctx, "fields", fields(ctx))
    {:noreply, ctx}
  end

  def handle_event("update_field", %{"field" => field, "value" => value}, ctx) do
    field = Enum.find(@option_fields, &(Atom.to_string(&1) == field))

    ctx =
      with true <- field != nil, {:ok, value} <- Options.cast(field, value) do
        update(ctx, :options, &Map.put(&1, field, value))
      else
        _invalid -> ctx
      end

    broadcast_event(ctx, "fields", fields(ctx))
    {:noreply, ctx}
  end

  def handle_event("update_send", %{} = send, ctx) do
    ctx = assign(ctx, send: Map.merge(ctx.assigns.send, Map.take(send, Map.keys(@default_send))))
    broadcast_event(ctx, "fields", fields(ctx))
    {:noreply, ctx}
  end

  def handle_event("send", %{}, ctx) do
    send = ctx.assigns.send

    result =
      with {:ok, data} <- Value.parse(send["value"], send["format"]),
           {:ok, line_ending} <- Value.line_ending(send["line_ending"]) do
        Port.write_async(port(ctx), data <> line_ending)
      end

    ctx =
      case result do
        :ok -> ctx
        {:error, reason} -> log(ctx, :error, Port.format_error(reason))
      end

    {:noreply, ctx}
  end

  def handle_event("clear", %{}, ctx) do
    ctx = update(ctx, :log, &Log.clear/1)
    broadcast_event(ctx, "log_cleared", %{})
    {:noreply, ctx}
  end

  def handle_event("disconnect", %{}, ctx) do
    Port.disconnect(port(ctx))
    {:noreply, ctx}
  end

  ## Events from the browser's Web Serial API

  def handle_event("connected", %{"info" => info} = connected, ctx) do
    # The options the browser opened the port with
    options =
      for field <- Options.open_fields(), into: %{} do
        case Options.cast(field, connected["options"][Atom.to_string(field)]) do
          {:ok, value} -> {field, value}
          :error -> {field, ctx.assigns.options[field]}
        end
      end

    Port.connected(port(ctx), %{
      usb_vendor_id: info["usbVendorId"],
      usb_product_id: info["usbProductId"],
      options: options
    })

    {:noreply, assign(ctx, owner: ctx.origin, error: nil)}
  end

  def handle_event("connect_error", %{"message" => message}, ctx) do
    ctx = assign(ctx, error: message)
    broadcast_event(ctx, "port", port_view(ctx))
    {:noreply, ctx}
  end

  def handle_event("disconnected", %{}, ctx) do
    if ctx.origin == ctx.assigns.owner, do: Port.disconnected(port(ctx))
    {:noreply, ctx}
  end

  def handle_event("data", {:binary, _info, data}, ctx) do
    if ctx.origin == ctx.assigns.owner do
      Port.deliver(ctx.assigns.port_id, {:data, data})
      {:noreply, log(ctx, :rx, data)}
    else
      {:noreply, ctx}
    end
  end

  def handle_event("read_error", %{"message" => message}, ctx) do
    {:noreply, log(ctx, :error, "read failed: " <> message)}
  end

  def handle_event("response", %{"ref" => ref} = response, ctx) do
    result =
      case response do
        %{"error" => message} -> {:error, message}
        %{"signals" => signals} -> {:ok, status_signals(signals)}
        %{} -> {:ok, nil}
      end

    Port.deliver(ctx.assigns.port_id, {:response, ref, result})
    {:noreply, ctx}
  end

  ## Messages from the Port server

  @impl true
  def handle_info({:kino_web_serial, :request, request}, ctx) do
    ctx =
      cond do
        ctx.assigns.owner == nil ->
          if request.ref do
            Port.deliver(ctx.assigns.port_id, {:response, request.ref, {:error, :not_connected}})
          end

          ctx

        request.op == :write ->
          info = %{ref: request.ref, op: "write"}
          send_event(ctx, ctx.assigns.owner, "request", {:binary, info, request.value})
          log(ctx, :tx, request.value)

        true ->
          send_event(ctx, ctx.assigns.owner, "request", %{
            ref: request.ref,
            op: Atom.to_string(request.op),
            signals: request[:signals] && browser_signals(request.signals)
          })

          ctx
      end

    {:noreply, ctx}
  end

  def handle_info({:kino_web_serial, :port_changed, info}, ctx) do
    ctx =
      case info.status do
        :connected -> assign(ctx, port: info)
        :disconnected -> assign(ctx, port: info, owner: nil)
      end

    broadcast_event(ctx, "port", port_view(ctx))
    {:noreply, ctx}
  end

  def handle_info({:kino_web_serial, :error, message}, ctx) do
    {:noreply, log(ctx, :error, message)}
  end

  ## Source

  @impl true
  def to_attrs(ctx) do
    options = Map.new(ctx.assigns.options, fn {key, value} -> {Atom.to_string(key), value} end)

    Map.merge(options, %{
      "port_id" => ctx.assigns.port_id,
      "variable" => ctx.assigns.variable,
      "send" => ctx.assigns.send,
      "display" => ctx.assigns.display
    })
  end

  @impl true
  def to_source(attrs) do
    quote do
      unquote(Macro.var(String.to_atom(attrs["variable"]), nil)) =
        KinoWebSerial.port(unquote(attrs["port_id"]))
    end
    |> Kino.SmartCell.quoted_to_string()
  end

  ## Helpers

  defp port(ctx), do: %Port{id: ctx.assigns.port_id}

  defp log(ctx, direction, data) do
    {log, entries} = Log.add(ctx.assigns.log, direction, data, System.os_time(:millisecond))
    broadcast_event(ctx, "log", Enum.map(entries, &entry_view/1))
    assign(ctx, log: log)
  end

  defp browser_signals(signals) do
    for {signal, value} <- signals, into: %{}, do: {Map.fetch!(@signals, signal), value}
  end

  defp status_signals(signals) do
    for {name, signal} <- @status_signals, into: %{}, do: {signal, signals[name] == true}
  end

  ## Views sent to the UI (plain maps, JSON encodable)

  defp fields(ctx) do
    ctx.assigns.options
    |> Map.merge(%{
      variable: ctx.assigns.variable,
      send: ctx.assigns.send,
      display: ctx.assigns.display,
      filters: Options.filters(ctx.assigns.options)
    })
  end

  defp port_view(ctx) do
    %{port: port, error: error} = ctx.assigns

    %{
      status: port.status,
      name: port_name(port),
      usb_vendor_id: Options.format_usb_id(port.usb_vendor_id),
      usb_product_id: Options.format_usb_id(port.usb_product_id),
      options: port.options,
      error: error
    }
  end

  defp port_name(%{status: :disconnected}), do: nil
  defp port_name(%{usb_vendor_id: nil}), do: "serial port"

  defp port_name(port) do
    "USB device " <>
      Options.format_usb_id(port.usb_vendor_id) <>
      ":" <> (Options.format_usb_id(port.usb_product_id) || "????")
  end

  defp entry_view(entry) do
    %{
      id: entry.id,
      direction: entry.direction,
      at: entry.at,
      hex: Value.to_hex(entry.data),
      text: entry_text(entry)
    }
  end

  # Errors are messages, data is shown as a line without its line ending
  defp entry_text(%{direction: :error, data: message}), do: message

  defp entry_text(%{data: data}) do
    data |> Value.trim_line_ending() |> Value.to_text()
  end
end
