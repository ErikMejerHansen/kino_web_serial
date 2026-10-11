# KinoWebSerial

A [Livebook](https://livebook.dev) Smart Cell and Elixir API for serial
ports, using the browser's
[Web Serial API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Serial_API).

You pick a port in the Smart Cell, for example an Arduino or another
USB serial device. Then you can send and receive data, either in the
cell or from Elixir code.

## Requirements

  * Livebook v0.13 or later
  * A Chromium based browser (Chrome, Edge) on desktop

## Installation

```elixir
Mix.install([
  {:kino_web_serial, "~> 0.1"}
])
```

## The Smart Cell

Add a **Web Serial** Smart Cell. Then:

1. Choose the baud rate and, if needed, the data bits, parity, stop
   bits and flow control. Enter a USB vendor and product ID (in hex,
   such as `2341`) to only offer matching ports.
2. Click **Connect** and pick a port in the browser dialog.
3. The monitor shows the data sent and received, as text or hex. Send
   data as text or hex (`01 ff`), with an optional line ending.

The cell saves your input in the notebook. When you evaluate it, the
port is bound to a variable (`serial` by default).

## The API

Browsers only let a user pick a port, so you always connect in the
Smart Cell. Everything else also works from code:

```elixir
# Bound by the Smart Cell
serial = KinoWebSerial.port("serial-...")

# Wait until the port is connected in the Smart Cell
:ok = KinoWebSerial.await_connected(serial)

# Subscribe before writing, to not miss the response
:ok = KinoWebSerial.subscribe(serial)
:ok = KinoWebSerial.write(serial, "status\n")

receive do
  {:kino_web_serial, :data, ^serial, data} -> data
end

# Write without waiting
:ok = KinoWebSerial.write_async(serial, <<0x01, 0xFF>>)

# Consume received data as lines...
serial
|> KinoWebSerial.lines()
|> Kino.listen(fn line -> IO.puts(line) end)

# ...or as raw chunks
serial
|> KinoWebSerial.stream()
|> Kino.listen(&IO.inspect/1)

# Control signals, such as toggling DTR to reset an Arduino
:ok = KinoWebSerial.set_signals(serial, data_terminal_ready: false)
:ok = KinoWebSerial.set_signals(serial, data_terminal_ready: true)
{:ok, %{clear_to_send: cts}} = KinoWebSerial.signals(serial)
```

See the `KinoWebSerial` module docs for all functions.

## Example: LEGO® SPIKE™ Prime

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2FErikMejerHansen%2Fkino_web_serial%2Fblob%2Fmain%2Fnotebooks%2Fspike_prime_usb.livemd)

[notebooks/spike_prime_usb.livemd](notebooks/spike_prime_usb.livemd)
connects to a SPIKE Prime hub over USB, using
[ExSPIKE](https://github.com/ErikMejerHansen/ex_spike) for the protocol.
It asks the hub for its info, shows its console output and sensor
readings, and uploads and runs a program.

## How it works

Each Smart Cell starts a `KinoWebSerial.Port` GenServer. It holds the
connection state and the subscribers, and runs browser operations
(writes, signals) one at a time, in order.

The state lives in Elixir. The browser keeps only what it has to: the
open `SerialPort` and its reader and writer. While the port is open,
the browser reads from it continuously and sends the data to Elixir.
The Smart Cell sends operations to the browser tab that opened the
port, and sends the results back.

## Development

```sh
mix deps.get
mix test
```

### Spec

The requirements are in [spec/kino_web_serial.spec.md](https://github.com/ErikMejerHansen/kino_web_serial/blob/main/spec/kino_web_serial.spec.md),
each with an ID such as `UI-5`. Tests declare the requirements they
verify with a tag:

```elixir
@tag spec: "UI-5"
test "shows when the port is lost" do
```

Requirements that tests can't fully cover are reviewed by hand and
recorded in [spec/reviews.exs](https://github.com/ErikMejerHansen/kino_web_serial/blob/main/spec/reviews.exs).

`mix spec` runs the tests and writes [spec/STATUS.md](https://github.com/ErikMejerHansen/kino_web_serial/blob/main/spec/STATUS.md),
which lists each requirement as tested, reviewed, failing or open.
Commit it together with spec and code changes. CI fails when it is out
of date.

### Releasing

1. Bump `@version` in `mix.exs` and merge to `main`.
2. In GitHub, run **Actions → Publish to Hex** on `main` with that
   version. Tick *Dry run* first to check the package without publishing.

The workflow runs all checks, publishes the package and docs to Hex,
and tags the release `vX.Y.Z`. It needs a `HEX_API_KEY` secret.

## License

MIT, see [LICENSE](https://github.com/ErikMejerHansen/kino_web_serial/blob/main/LICENSE).
