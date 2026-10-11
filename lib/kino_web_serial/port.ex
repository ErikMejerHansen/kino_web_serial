defmodule KinoWebSerial.Port do
  @moduledoc """
  A serial port selected through a Smart Cell.

  The struct is a handle, used with the functions in `KinoWebSerial`.
  It identifies the Smart Cell rather than a physical port, so it stays
  valid across disconnects and reconnects.

  Behind the handle runs a `GenServer` that owns the port state: the
  connection, the subscribers, and a queue of operations for the
  browser. Operations run one at a time, in order.
  """

  use GenServer

  require Logger

  @enforce_keys [:id]
  defstruct [:id]

  @type t :: %__MODULE__{id: String.t()}

  @type info :: %{
          id: String.t(),
          status: :connected | :disconnected,
          usb_vendor_id: non_neg_integer() | nil,
          usb_product_id: non_neg_integer() | nil,
          options: KinoWebSerial.Options.t() | nil
        }

  @type signals :: %{
          optional(:data_terminal_ready) => boolean(),
          optional(:request_to_send) => boolean(),
          optional(:break) => boolean()
        }

  @type status_signals :: %{
          clear_to_send: boolean(),
          data_set_ready: boolean(),
          data_carrier_detect: boolean(),
          ring_indicator: boolean()
        }

  @default_timeout 5_000

  ## Client (used by KinoWebSerial and the Smart Cell)

  @doc false
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  @doc false
  def whereis(%__MODULE__{id: id}), do: lookup(id)

  @doc false
  def info(port), do: call(port, :info, @default_timeout)

  @doc false
  def await_connected(port, timeout), do: call(port, :await_connected, timeout)

  @doc false
  def disconnect(port), do: call(port, :disconnect, @default_timeout)

  @doc false
  def write(port, value, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    call(port, {:request, %{op: :write, value: IO.iodata_to_binary(value)}, timeout}, timeout)
  end

  @doc false
  def write_async(port, value) do
    call(port, {:write_async, IO.iodata_to_binary(value)}, @default_timeout)
  end

  @doc false
  def set_signals(port, signals, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    call(port, {:request, %{op: :set_signals, signals: signals}, timeout}, timeout)
  end

  @doc false
  def signals(port, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    call(port, {:request, %{op: :get_signals}, timeout}, timeout)
  end

  @doc false
  def subscribe(port, pid), do: call(port, {:subscribe, pid}, @default_timeout)

  @doc false
  def unsubscribe(port, pid), do: call(port, {:unsubscribe, pid}, @default_timeout)

  @doc false
  # Called by the bridge once the browser opened a port. `info` has the
  # shape of `t:info/0`, without `:id` and `:status`.
  def connected(port, info), do: cast(port, {:connected, info})

  @doc false
  # Called by the bridge when the browser lost the port.
  def disconnected(port), do: cast(port, :disconnected)

  @doc false
  # Delivers data or a browser response to the port server.
  def deliver(id, message) do
    if pid = lookup(id), do: GenServer.cast(pid, message)
    :ok
  end

  defp call(port, message, timeout) do
    case whereis(port) do
      nil ->
        {:error, :not_found}

      pid ->
        try do
          # Leave room for the server side timeout to reply first
          GenServer.call(pid, message, add_margin(timeout))
        catch
          :exit, {:timeout, _} -> {:error, :timeout}
          :exit, _ -> {:error, :not_found}
        end
    end
  end

  defp add_margin(:infinity), do: :infinity
  defp add_margin(timeout), do: timeout + 1_000

  defp cast(port, message) do
    if pid = whereis(port), do: GenServer.cast(pid, message)
    :ok
  end

  defp via(id), do: {:via, Registry, {KinoWebSerial.Registry, {:port, id}}}

  defp lookup(id) do
    case Registry.lookup(KinoWebSerial.Registry, {:port, id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  ## Server

  @impl true
  def init(opts) do
    bridge = Keyword.fetch!(opts, :bridge)

    {:ok,
     %{
       id: Keyword.fetch!(opts, :id),
       bridge: bridge,
       bridge_ref: Process.monitor(bridge),
       status: :disconnected,
       usb_vendor_id: nil,
       usb_product_id: nil,
       options: nil,
       subscribers: %{},
       waiters: [],
       queue: :queue.new(),
       in_flight: nil
     }}
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, {:ok, snapshot(state)}, state}

  def handle_call(:await_connected, from, state) do
    case state.status do
      :connected -> {:reply, :ok, state}
      :disconnected -> {:noreply, update_in(state.waiters, &[from | &1])}
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, remove_subscriber(state, pid)}
  end

  def handle_call(_request, _from, %{status: :disconnected} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:disconnect, _from, state) do
    send(state.bridge, {:kino_web_serial, :request, %{ref: nil, op: :close}})
    {:reply, :ok, mark_disconnected(state)}
  end

  def handle_call({:request, request, timeout}, from, state) do
    {:noreply, enqueue(state, Map.merge(request, %{from: from, timeout: timeout}))}
  end

  def handle_call({:write_async, value}, _from, state) do
    request = %{op: :write, value: value, from: nil, timeout: @default_timeout}
    {:reply, :ok, enqueue(state, request)}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    state =
      if Map.has_key?(state.subscribers, pid),
        do: state,
        else: put_in(state.subscribers[pid], Process.monitor(pid))

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:connected, info}, state) do
    # A new port replaces the old one
    state = if state.status == :connected, do: mark_disconnected(state), else: state

    for from <- state.waiters, do: GenServer.reply(from, :ok)

    state =
      Map.merge(state, %{
        status: :connected,
        usb_vendor_id: info[:usb_vendor_id],
        usb_product_id: info[:usb_product_id],
        options: info[:options],
        waiters: []
      })

    {:noreply, changed(state)}
  end

  def handle_cast(:disconnected, %{status: :connected} = state) do
    {:noreply, mark_disconnected(state)}
  end

  def handle_cast(:disconnected, state), do: {:noreply, state}

  def handle_cast({:data, data}, state) do
    port = %__MODULE__{id: state.id}
    for {pid, _ref} <- state.subscribers, do: send(pid, {:kino_web_serial, :data, port, data})
    {:noreply, state}
  end

  def handle_cast({:response, ref, result}, %{in_flight: %{ref: ref} = request} = state) do
    Process.cancel_timer(request.timer)
    complete(state, request, result)
    {:noreply, dispatch(%{state | in_flight: nil})}
  end

  def handle_cast({:response, _stale_ref, _result}, state), do: {:noreply, state}

  @impl true
  def handle_info({:request_timeout, ref}, %{in_flight: %{ref: ref} = request} = state) do
    complete(state, request, {:error, :timeout})
    {:noreply, dispatch(%{state | in_flight: nil})}
  end

  def handle_info({:request_timeout, _stale_ref}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{bridge_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, remove_subscriber(state, pid)}
  end

  @impl true
  def terminate(_reason, state) do
    fail_pending(state)
    notify_disconnected(state)
    :ok
  end

  defp mark_disconnected(state) do
    fail_pending(state)
    notify_disconnected(state)

    for {_pid, ref} <- state.subscribers, do: Process.demonitor(ref, [:flush])

    changed(%{
      state
      | status: :disconnected,
        usb_vendor_id: nil,
        usb_product_id: nil,
        options: nil,
        subscribers: %{},
        queue: :queue.new(),
        in_flight: nil
    })
  end

  defp fail_pending(state) do
    if state.in_flight, do: Process.cancel_timer(state.in_flight.timer)

    pending = if state.in_flight, do: [state.in_flight], else: []

    for request <- pending ++ :queue.to_list(state.queue) do
      reply(request.from, {:error, :disconnected})
    end
  end

  defp notify_disconnected(state) do
    port = %__MODULE__{id: state.id}
    for {pid, _ref} <- state.subscribers, do: send(pid, {:kino_web_serial, :disconnected, port})
  end

  defp remove_subscriber(state, pid) do
    {ref, subscribers} = Map.pop(state.subscribers, pid)
    if ref, do: Process.demonitor(ref, [:flush])
    %{state | subscribers: subscribers}
  end

  ## Request queue

  defp enqueue(state, request) do
    dispatch(%{state | queue: :queue.in(request, state.queue)})
  end

  defp dispatch(%{in_flight: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, request}, queue} ->
        ref = System.unique_integer([:positive])
        timer = Process.send_after(self(), {:request_timeout, ref}, request.timeout)

        message =
          request
          |> Map.take([:op, :value, :signals])
          |> Map.put(:ref, ref)

        send(state.bridge, {:kino_web_serial, :request, message})

        %{state | queue: queue, in_flight: Map.merge(request, %{ref: ref, timer: timer})}

      {:empty, _queue} ->
        state
    end
  end

  defp dispatch(state), do: state

  # Nobody waits for async writes, so their failures are logged and
  # shown in the Smart Cell
  defp complete(state, %{from: nil} = request, {:error, reason}) do
    message = "#{request.op} failed: #{format_error(reason)}"
    Logger.warning("[KinoWebSerial] " <> message)
    send(state.bridge, {:kino_web_serial, :error, message})
  end

  defp complete(_state, %{from: nil}, {:ok, _}), do: :ok

  defp complete(_state, %{op: :get_signals} = request, {:ok, signals}),
    do: reply(request.from, {:ok, signals})

  defp complete(_state, request, {:ok, _}), do: reply(request.from, :ok)
  defp complete(_state, request, {:error, reason}), do: reply(request.from, {:error, reason})

  defp reply(nil, _message), do: :ok
  defp reply(from, message), do: GenServer.reply(from, message)

  defp changed(state) do
    send(state.bridge, {:kino_web_serial, :port_changed, snapshot(state)})
    state
  end

  defp snapshot(state) do
    Map.take(state, [:id, :status, :usb_vendor_id, :usb_product_id, :options])
  end

  @doc false
  def format_error(reason) when is_binary(reason), do: reason
  def format_error(reason), do: reason |> to_string() |> String.replace("_", " ")
end
