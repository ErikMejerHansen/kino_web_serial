defmodule KinoWebSerial do
  @moduledoc """
  Web Serial for Livebook.

  Add the **Web Serial** Smart Cell to a notebook, pick the connection
  options and click **Connect**. Browsers only let a user pick a port,
  so connecting always happens in the Smart Cell. Everything else can be
  done from code, using the port bound by the cell:

      serial = KinoWebSerial.port("serial-...")
      :ok = KinoWebSerial.await_connected(serial)

      :ok = KinoWebSerial.subscribe(serial)
      :ok = KinoWebSerial.write(serial, "hello\\n")

      receive do
        {:kino_web_serial, :data, ^serial, data} -> data
      end

  ## Receiving data

  The browser reads from the port all the time it is open. Subscribers
  receive a message for every chunk of data it reads:

      {:kino_web_serial, :data, port, binary}

  and, when the port disconnects:

      {:kino_web_serial, :disconnected, port}

  Serial ports have no message boundaries, so a chunk can hold part of
  a message or several messages. `lines/1` puts lines back together.

  Subscribe before writing a request, to not miss the response.

  ## Errors

  Operations return `{:error, reason}`, where `reason` is one of
  `:not_found`, `:not_connected`, `:disconnected`, `:timeout`, or a
  message from the browser.
  """

  alias KinoWebSerial.Port

  @type error :: {:error, atom() | String.t()}

  @doc """
  Returns the port handle for a Smart Cell's port id.

  The Smart Cell generates this call for you.
  """
  @spec port(String.t()) :: Port.t()
  def port(id) when is_binary(id), do: %Port{id: id}

  @doc """
  Returns information about the port and the options it was opened with.

  `:usb_vendor_id` and `:usb_product_id` are `nil` when the port is
  not a USB device.
  """
  @spec info(Port.t()) :: {:ok, Port.info()} | error()
  def info(%Port{} = port), do: Port.info(port)

  @doc """
  Returns `true` when the port is connected.
  """
  @spec connected?(Port.t()) :: boolean()
  def connected?(%Port{} = port), do: match?({:ok, %{status: :connected}}, info(port))

  @doc """
  Blocks until the port is connected through the Smart Cell.

  Returns `:ok` immediately if it is connected already.
  """
  @spec await_connected(Port.t(), timeout()) :: :ok | error()
  def await_connected(%Port{} = port, timeout \\ :infinity) do
    Port.await_connected(port, timeout)
  end

  @doc """
  Closes the port.
  """
  @spec disconnect(Port.t()) :: :ok | error()
  def disconnect(%Port{} = port), do: Port.disconnect(port)

  @doc """
  Writes data to the port and waits until the browser has written it.

  ## Options

    * `:timeout` - how long to wait for the browser, defaults to `5_000` ms

  """
  @spec write(Port.t(), iodata(), keyword()) :: :ok | error()
  def write(%Port{} = port, data, opts \\ []), do: Port.write(port, data, opts)

  @doc """
  Writes data to the port without waiting for it to be written.

  Writes are still sent in order. Failures are logged and shown in the
  Smart Cell.
  """
  @spec write_async(Port.t(), iodata()) :: :ok | error()
  def write_async(%Port{} = port, data), do: Port.write_async(port, data)

  @doc """
  Sets control signals of the port.

  Takes any of `:data_terminal_ready` (DTR), `:request_to_send` (RTS)
  and `:break`. Signals that are not given are left as they are.

      # Resets many Arduino boards
      :ok = KinoWebSerial.set_signals(serial, data_terminal_ready: false)
      :ok = KinoWebSerial.set_signals(serial, data_terminal_ready: true)

  ## Options

    * `:timeout` - how long to wait for the browser, defaults to `5_000` ms

  """
  @spec set_signals(Port.t(), keyword() | Port.signals(), keyword()) :: :ok | error()
  def set_signals(%Port{} = port, signals, opts \\ []) do
    signals = Map.new(signals)

    case Map.keys(signals) -- [:data_terminal_ready, :request_to_send, :break] do
      [] -> Port.set_signals(port, signals, opts)
      unknown -> raise ArgumentError, "unknown signals: #{inspect(unknown)}"
    end
  end

  @doc """
  Reads the status signals of the port.

      {:ok, %{clear_to_send: true, data_set_ready: true,
              data_carrier_detect: false, ring_indicator: false}}

  Accepts the same options as `set_signals/3`.
  """
  @spec signals(Port.t(), keyword()) :: {:ok, Port.status_signals()} | error()
  def signals(%Port{} = port, opts \\ []), do: Port.signals(port, opts)

  @doc """
  Subscribes the calling process to the data received from the port.

  See the "Receiving data" section in the module docs for the messages
  sent. Subscriptions end when the port disconnects.
  """
  @spec subscribe(Port.t()) :: :ok | error()
  def subscribe(%Port{} = port), do: Port.subscribe(port, self())

  @doc """
  Unsubscribes the calling process from the port.
  """
  @spec unsubscribe(Port.t()) :: :ok | error()
  def unsubscribe(%Port{} = port), do: Port.unsubscribe(port, self())

  @doc """
  Returns a stream of the chunks of data received from the port.

  The stream subscribes when consumed and halts when the port
  disconnects. It works well with `Kino.listen/2`:

      serial
      |> KinoWebSerial.stream()
      |> Kino.listen(fn data -> IO.inspect(data) end)

  """
  @spec stream(Port.t()) :: Enumerable.t()
  def stream(%Port{} = port) do
    Stream.resource(
      fn ->
        case subscribe(port) do
          :ok -> port
          {:error, reason} -> raise ArgumentError, "could not subscribe: #{inspect(reason)}"
        end
      end,
      fn port ->
        receive do
          {:kino_web_serial, :data, ^port, data} -> {[data], port}
          {:kino_web_serial, :disconnected, ^port} -> {:halt, port}
        end
      end,
      fn port -> unsubscribe(port) end
    )
  end

  @doc """
  Returns a stream of the lines received from the port.

  Lines are split on `"\\n"`, and the line ending (`"\\n"` or `"\\r\\n"`)
  is removed. When the port disconnects, an unfinished last line is
  emitted as is.

      serial
      |> KinoWebSerial.lines()
      |> Kino.listen(fn line -> IO.puts(line) end)

  """
  @spec lines(Port.t()) :: Enumerable.t()
  def lines(%Port{} = port) do
    Stream.transform(
      stream(port),
      fn -> "" end,
      fn data, buffer ->
        [rest | lines] = (buffer <> data) |> String.split("\n") |> Enum.reverse()
        {lines |> Enum.reverse() |> Enum.map(&trim_carriage_return/1), rest}
      end,
      fn
        "" -> {[], ""}
        rest -> {[rest], ""}
      end,
      fn _buffer -> :ok end
    )
  end

  defp trim_carriage_return(line) do
    if String.ends_with?(line, "\r"), do: binary_part(line, 0, byte_size(line) - 1), else: line
  end
end
