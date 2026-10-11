defmodule KinoWebSerial.SmartCellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoWebSerial.SmartCell

  setup :configure_livebook_bridge

  @browser_port %{
    "info" => %{"usbVendorId" => 0x2341, "usbProductId" => 0x0043},
    "options" => %{
      "baud_rate" => 9600,
      "data_bits" => 8,
      "parity" => "none",
      "stop_bits" => 1,
      "flow_control" => "none"
    }
  }

  describe "a new cell" do
    test "binds a port to a variable" do
      {_kino, source} = start_smart_cell!(SmartCell, %{})

      assert source =~ ~r/^serial\d* = KinoWebSerial.port\("serial-[\w-]+"\)$/
    end

    @tag spec: ["UI-1", "UI-2"]
    test "shows the connection options with sensible defaults" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})

      assert %{fields: fields, choices: choices} = connect(kino)

      assert %{
               baud_rate: 115_200,
               data_bits: 8,
               parity: "none",
               stop_bits: 1,
               flow_control: "none",
               usb_vendor_id: "",
               usb_product_id: "",
               filters: []
             } = fields

      assert 9600 in choices.baud_rate
      assert choices.parity == ["none", "even", "odd"]
    end

    @tag spec: "UI-5"
    test "shows a disconnected port" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})

      assert %{port: %{status: :disconnected, name: nil}, log: []} = connect(kino)
    end
  end

  describe "a saved cell" do
    @tag spec: "UI-14"
    test "restores the user input" do
      attrs = %{
        "port_id" => "serial-saved",
        "variable" => "arduino",
        "baud_rate" => 9600,
        "data_bits" => 7,
        "parity" => "even",
        "stop_bits" => 2,
        "flow_control" => "hardware",
        "usb_vendor_id" => "2341",
        "usb_product_id" => "",
        "send" => %{"value" => "ping", "format" => "text", "line_ending" => "crlf"},
        "display" => "hex"
      }

      {kino, source} = start_smart_cell!(SmartCell, attrs)

      assert source == ~s/arduino = KinoWebSerial.port("serial-saved")/

      assert %{fields: fields} = connect(kino)

      assert %{
               variable: "arduino",
               baud_rate: 9600,
               data_bits: 7,
               parity: "even",
               stop_bits: 2,
               flow_control: "hardware",
               usb_vendor_id: "2341",
               send: %{"value" => "ping", "line_ending" => "crlf"},
               display: "hex"
             } = fields
    end

    @tag spec: "UI-14"
    test "falls back to defaults for invalid saved options" do
      {kino, _source} = start_smart_cell!(SmartCell, %{"baud_rate" => -1, "parity" => "mark"})

      assert %{fields: %{baud_rate: 115_200, parity: "none"}} = connect(kino)
    end
  end

  describe "editing the fields" do
    @tag spec: ["UI-1", "UI-14"]
    test "persists the connection options" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})

      push_event(kino, "update_field", %{"field" => "baud_rate", "value" => " 9600 "})
      assert_smart_cell_update(kino, %{"baud_rate" => 9600}, _source)

      push_event(kino, "update_field", %{"field" => "parity", "value" => "odd"})
      assert_smart_cell_update(kino, %{"parity" => "odd"}, _source)

      push_event(kino, "update_field", %{"field" => "stop_bits", "value" => "2"})
      assert_smart_cell_update(kino, %{"stop_bits" => 2}, _source)

      assert_broadcast_event(kino, "fields", %{baud_rate: 9600, parity: "odd", stop_bits: 2})
    end

    @tag spec: "UI-1"
    test "rejects invalid options" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})

      push_event(kino, "update_field", %{"field" => "baud_rate", "value" => "fast"})
      assert_broadcast_event(kino, "fields", %{baud_rate: 115_200})

      push_event(kino, "update_field", %{"field" => "data_bits", "value" => "9"})
      assert_broadcast_event(kino, "fields", %{data_bits: 8})
    end

    @tag spec: ["UI-2", "UI-4", "UI-14"]
    test "turns the USB IDs into port filters for the browser" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})

      push_event(kino, "update_field", %{"field" => "usb_vendor_id", "value" => "0x2341"})
      assert_broadcast_event(kino, "fields", %{filters: [%{usbVendorId: 0x2341}]})

      push_event(kino, "update_field", %{"field" => "usb_product_id", "value" => "43"})

      assert_broadcast_event(kino, "fields", %{
        usb_product_id: "43",
        filters: [%{usbVendorId: 0x2341, usbProductId: 0x0043}]
      })

      assert_smart_cell_update(kino, %{"usb_vendor_id" => "0x2341"}, _source)
    end

    @tag spec: "UI-2"
    test "rejects invalid USB IDs" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})

      push_event(kino, "update_field", %{"field" => "usb_vendor_id", "value" => "arduino"})

      assert_broadcast_event(kino, "fields", %{usb_vendor_id: "", filters: []})
    end

    @tag spec: "UI-14"
    test "renames the variable in the generated code" do
      {kino, _source} = start_smart_cell!(SmartCell, %{"port_id" => "serial-rename"})

      push_event(kino, "update_field", %{"field" => "variable", "value" => "gps"})

      assert_smart_cell_update(
        kino,
        %{"variable" => "gps"},
        ~s/gps = KinoWebSerial.port("serial-rename")/
      )
    end

    @tag spec: "UI-14"
    test "rejects invalid variable names" do
      {kino, _source} = start_smart_cell!(SmartCell, %{"variable" => "serial"})

      push_event(kino, "update_field", %{"field" => "variable", "value" => "1nvalid"})

      assert_broadcast_event(kino, "fields", %{variable: "serial"})
    end
  end

  describe "connecting in the browser" do
    @tag spec: ["UI-5", "UI-6"]
    test "shows the connected port and how it was opened" do
      {_kino, _source, view} = given_a_connected_cell()

      assert %{
               status: :connected,
               name: "USB device 2341:0043",
               usb_vendor_id: "2341",
               usb_product_id: "0043",
               options: %{baud_rate: 9600, data_bits: 8, parity: "none", stop_bits: 1}
             } = view
    end

    @tag spec: "UI-6"
    test "shows ports that are not USB devices" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})
      connect(kino)

      push_event(kino, "connected", %{@browser_port | "info" => %{}})

      assert_broadcast_event(kino, "port", %{status: :connected, name: "serial port"})
    end

    @tag spec: "API-1"
    test "makes the port available to code" do
      {_kino, source, _view} = given_a_connected_cell()

      port = evaluate(source)

      assert KinoWebSerial.connected?(port)
      assert {:ok, %{options: %{baud_rate: 9600}}} = KinoWebSerial.info(port)
    end

    @tag spec: "UI-5"
    test "shows errors reported by the browser" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})
      connect(kino)

      push_event(kino, "connect_error", %{"message" => "No port selected by the user."})

      assert_broadcast_event(kino, "port", %{
        status: :disconnected,
        error: "No port selected by the user."
      })
    end

    @tag spec: "UI-5"
    test "shows when the port is lost" do
      {kino, _source, _view} = given_a_connected_cell()

      push_event(kino, "disconnected", %{})

      assert_broadcast_event(kino, "port", %{status: :disconnected, name: nil})
    end
  end

  describe "using the UI" do
    @tag spec: ["UI-8", "UI-9", "UI-14"]
    test "sends the entered text with the line ending and shows it" do
      {kino, _source, _view} = given_a_connected_cell()

      push_event(kino, "update_send", %{
        "value" => "AT",
        "format" => "text",
        "line_ending" => "crlf"
      })

      push_event(kino, "send", %{})

      assert_send_event(kino, "request", {:binary, %{op: "write"}, "AT\r\n"})
      assert_broadcast_event(kino, "log", [%{direction: :tx, text: "AT", hex: "41 54 0d 0a"}])

      assert_smart_cell_update(
        kino,
        %{"send" => %{"value" => "AT", "line_ending" => "crlf"}},
        _source
      )
    end

    @tag spec: "UI-8"
    test "sends hex input as bytes" do
      {kino, _source, _view} = given_a_connected_cell()

      push_event(kino, "update_send", %{
        "value" => "01 ff",
        "format" => "hex",
        "line_ending" => "none"
      })

      push_event(kino, "send", %{})

      assert_send_event(kino, "request", {:binary, %{op: "write"}, <<1, 255>>})
    end

    @tag spec: "UI-8"
    test "shows invalid input instead of sending it" do
      {kino, _source, _view} = given_a_connected_cell()

      push_event(kino, "update_send", %{
        "value" => "nope",
        "format" => "hex",
        "line_ending" => "none"
      })

      push_event(kino, "send", %{})

      assert_broadcast_event(kino, "log", [%{direction: :error, text: "invalid hex value"}])
      refute_receive {:event, "request", _, _}
    end

    @tag spec: "UI-8"
    test "shows failed writes" do
      {kino, _source, _view} = given_a_connected_cell()

      push_event(kino, "send", %{})
      assert_send_event(kino, "request", {:binary, %{ref: ref}, "\n"})

      ExUnit.CaptureLog.capture_log(fn ->
        push_event(kino, "response", %{"ref" => ref, "error" => "The device has been lost."})

        assert_broadcast_event(kino, "log", [
          %{direction: :error, text: "write failed: The device has been lost."}
        ])
      end)
    end

    @tag spec: "UI-7"
    test "shows the received data as lines" do
      {kino, _source, _view} = given_a_connected_cell()

      receive_data(kino, "temp=2")
      assert_broadcast_event(kino, "log", [%{id: id, direction: :rx, text: "temp=2"}])

      receive_data(kino, "1.5\r\nok")

      assert_broadcast_event(kino, "log", [
        %{id: ^id, text: "temp=21.5", hex: "74 65 6d 70 3d 32 31 2e 35 0d 0a"},
        %{direction: :rx, text: "ok"}
      ])
    end

    @tag spec: "UI-7"
    test "shows control characters and binary data" do
      {kino, _source, _view} = given_a_connected_cell()

      receive_data(kino, <<0, 1, "a\tb", 255>>)

      assert_broadcast_event(kino, "log", [
        %{text: "\\x00\\x01a\\tb\\xff", hex: "00 01 61 09 62 ff"}
      ])
    end

    @tag spec: ["UI-10", "UI-14"]
    test "switches between text and hex" do
      {kino, _source} = start_smart_cell!(SmartCell, %{})

      push_event(kino, "update_field", %{"field" => "display", "value" => "hex"})

      assert_broadcast_event(kino, "fields", %{display: "hex"})
      assert_smart_cell_update(kino, %{"display" => "hex"}, _source)
    end

    @tag spec: "UI-11"
    test "clears the shown data" do
      {kino, _source, _view} = given_a_connected_cell()
      receive_data(kino, "hello\n")

      push_event(kino, "clear", %{})

      assert_broadcast_event(kino, "log_cleared", %{})
      assert %{log: []} = connect(kino)
    end

    @tag spec: "UI-12"
    test "closes the port on Disconnect" do
      {kino, _source, _view} = given_a_connected_cell()

      push_event(kino, "disconnect", %{})

      assert_send_event(kino, "request", %{op: "close"})
      assert_broadcast_event(kino, "port", %{status: :disconnected})
    end

    @tag spec: "UI-13"
    test "shows read errors" do
      {kino, _source, _view} = given_a_connected_cell()

      push_event(kino, "read_error", %{"message" => "Framing error."})

      assert_broadcast_event(kino, "log", [
        %{direction: :error, text: "read failed: Framing error."}
      ])
    end
  end

  describe "using the API" do
    @tag spec: ["API-2", "UI-7"]
    test "delivers data received in the browser to subscribers" do
      {kino, source, _view} = given_a_connected_cell()
      port = evaluate(source)
      :ok = KinoWebSerial.subscribe(port)

      receive_data(kino, "hello")

      assert_receive {:kino_web_serial, :data, ^port, "hello"}
    end

    @tag spec: ["API-3", "UI-9"]
    test "forwards writes to the browser and shows them" do
      {kino, source, _view} = given_a_connected_cell()
      port = evaluate(source)

      writing = Task.async(fn -> KinoWebSerial.write(port, "hi") end)

      assert_send_event(kino, "request", {:binary, %{op: "write", ref: ref}, "hi"})
      push_event(kino, "response", %{"ref" => ref})

      assert Task.await(writing) == :ok
      assert_broadcast_event(kino, "log", [%{direction: :tx, text: "hi"}])
    end

    @tag spec: "API-4"
    test "forwards signals to the browser" do
      {kino, source, _view} = given_a_connected_cell()
      port = evaluate(source)

      setting = Task.async(fn -> KinoWebSerial.set_signals(port, data_terminal_ready: false) end)

      assert_send_event(kino, "request", %{
        op: "set_signals",
        ref: ref,
        signals: %{"dataTerminalReady" => false}
      })

      push_event(kino, "response", %{"ref" => ref})
      assert Task.await(setting) == :ok

      reading = Task.async(fn -> KinoWebSerial.signals(port) end)

      assert_send_event(kino, "request", %{op: "get_signals", ref: ref})

      push_event(kino, "response", %{
        "ref" => ref,
        "signals" => %{
          "clearToSend" => true,
          "dataSetReady" => false,
          "dataCarrierDetect" => false,
          "ringIndicator" => false
        }
      })

      assert {:ok, %{clear_to_send: true, data_set_ready: false}} = Task.await(reading)
    end

    @tag spec: "API-1"
    test "can disconnect the port" do
      {kino, source, _view} = given_a_connected_cell()

      assert KinoWebSerial.disconnect(evaluate(source)) == :ok

      assert_send_event(kino, "request", %{op: "close"})
      assert_broadcast_event(kino, "port", %{status: :disconnected})
    end
  end

  defp given_a_connected_cell do
    {kino, source} = start_smart_cell!(SmartCell, %{})
    connect(kino)
    push_event(kino, "connected", @browser_port)
    assert_broadcast_event(kino, "port", %{status: :connected} = view)
    {kino, source, view}
  end

  defp receive_data(kino, data), do: push_event(kino, "data", {:binary, %{}, data})

  defp evaluate(source) do
    {port, _binding} = Code.eval_string(source)
    port
  end
end
