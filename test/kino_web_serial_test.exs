defmodule KinoWebSerialTest do
  use KinoWebSerial.SerialCase, async: true

  describe "a port that is not connected" do
    @describetag spec: "API-1"

    test "reports that it is disconnected" do
      %{port: port} = given_a_port()

      refute KinoWebSerial.connected?(port)
      assert {:ok, %{status: :disconnected, options: nil}} = KinoWebSerial.info(port)
    end

    test "can be awaited until the user connects it" do
      %{port: port} = given_a_port()

      waiting = Task.async(fn -> KinoWebSerial.await_connected(port) end)
      when_the_user_connects(port)

      assert Task.await(waiting) == :ok
      assert KinoWebSerial.connected?(port)
    end

    test "times out when awaited for too long" do
      %{port: port} = given_a_port()

      assert KinoWebSerial.await_connected(port, 10) == {:error, :timeout}
    end

    test "cannot be written, subscribed to or disconnected" do
      %{port: port} = given_a_port()

      assert KinoWebSerial.write(port, "hello") == {:error, :not_connected}
      assert KinoWebSerial.write_async(port, "hello") == {:error, :not_connected}
      assert KinoWebSerial.subscribe(port) == {:error, :not_connected}
      assert KinoWebSerial.disconnect(port) == {:error, :not_connected}
      refute_browser_request(_any)
    end
  end

  describe "a port without a Smart Cell" do
    @describetag spec: "API-1"

    test "is not found" do
      port = KinoWebSerial.port("serial-unknown")

      assert KinoWebSerial.info(port) == {:error, :not_found}
      assert KinoWebSerial.write(port, "hello") == {:error, :not_found}
      refute KinoWebSerial.connected?(port)
    end
  end

  describe "a connected port" do
    @describetag spec: "API-1"

    test "tells which device it is and how it was opened" do
      %{port: port} = given_a_connected_port()

      assert {:ok, info} = KinoWebSerial.info(port)
      assert %{status: :connected, usb_vendor_id: 0x2341, usb_product_id: 0x0043} = info
      assert info.options == options()
    end

    test "can be disconnected" do
      %{port: port} = given_a_connected_port()

      assert KinoWebSerial.disconnect(port) == :ok

      assert_browser_request(:close)
      refute KinoWebSerial.connected?(port)
      assert KinoWebSerial.write(port, "hello") == {:error, :not_connected}
    end

    test "can be connected again after it was lost" do
      %{port: port} = given_a_connected_port()

      when_the_port_disconnects(port)
      when_the_user_connects(port)

      assert KinoWebSerial.write(port, "hello") == :ok
    end
  end

  describe "writing to a port" do
    @describetag spec: "API-3"

    test "sends the data and waits for the browser to write it" do
      %{port: port} = given_a_connected_port()

      assert KinoWebSerial.write(port, "hello\n") == :ok

      assert %{value: "hello\n"} = assert_browser_request(:write)
    end

    test "accepts iodata" do
      %{port: port} = given_a_connected_port()

      assert KinoWebSerial.write(port, ["he", ?l, "lo", <<0>>]) == :ok

      assert %{value: <<"hello", 0>>} = assert_browser_request(:write)
    end

    test "returns the error reported by the browser" do
      %{port: port} = given_a_connected_port(write: {:error, "The device has been lost."})

      assert KinoWebSerial.write(port, "hello") == {:error, "The device has been lost."}
    end

    test "times out when the browser does not answer" do
      %{port: port} = given_a_connected_port(write: :no_reply)

      assert KinoWebSerial.write(port, "hello", timeout: 10) == {:error, :timeout}
    end

    test "fails when the port disconnects while waiting" do
      %{port: port} = given_a_connected_port(write: :no_reply)

      writing = Task.async(fn -> KinoWebSerial.write(port, "hello") end)
      assert_browser_request(:write)
      when_the_port_disconnects(port)

      assert Task.await(writing) == {:error, :disconnected}
    end

    test "asynchronously returns right away" do
      %{port: port} = given_a_connected_port(write: :no_reply)

      assert KinoWebSerial.write_async(port, "hello") == :ok

      assert %{value: "hello"} = assert_browser_request(:write)
    end

    test "asynchronously still sends one write at a time, in order" do
      %{port: port} = given_a_connected_port(write: :no_reply)

      KinoWebSerial.write_async(port, "first")
      KinoWebSerial.write_async(port, "second")

      first = assert_browser_request(:write)
      assert first.value == "first"
      refute_browser_request(:write)

      when_the_browser_completes(port, first, {:ok, nil})

      assert %{value: "second"} = assert_browser_request(:write)
    end

    test "asynchronously reports failures to the Smart Cell" do
      %{port: port} = given_a_connected_port(write: {:error, "The device has been lost."})

      ExUnit.CaptureLog.capture_log(fn ->
        KinoWebSerial.write_async(port, "hello")
        assert_receive {:kino_web_serial, :error, "write failed: The device has been lost."}
      end)
    end
  end

  describe "subscribing to a port" do
    @describetag spec: "API-2"

    test "delivers every chunk of data received" do
      %{port: port} = given_a_connected_port()
      :ok = KinoWebSerial.subscribe(port)

      when_the_port_receives(port, "hel")
      when_the_port_receives(port, "lo\r\n")

      assert_receive {:kino_web_serial, :data, ^port, "hel"}
      assert_receive {:kino_web_serial, :data, ^port, "lo\r\n"}
    end

    test "delivers data to every subscriber" do
      %{port: port} = given_a_connected_port()
      test = self()

      Task.start_link(fn ->
        :ok = KinoWebSerial.subscribe(port)
        send(test, :subscribed)
        assert_receive {:kino_web_serial, :data, ^port, data}
        send(test, {:other_subscriber, data})
      end)

      assert_receive :subscribed
      :ok = KinoWebSerial.subscribe(port)
      when_the_port_receives(port, "hi")

      assert_receive {:kino_web_serial, :data, ^port, "hi"}
      assert_receive {:other_subscriber, "hi"}
    end

    test "stops delivering data after unsubscribing" do
      %{port: port} = given_a_connected_port()
      :ok = KinoWebSerial.subscribe(port)

      assert KinoWebSerial.unsubscribe(port) == :ok
      when_the_port_receives(port, "hello")

      refute_receive {:kino_web_serial, :data, _, _}
    end

    test "tells the subscriber when the port disconnects, and ends the subscription" do
      %{port: port} = given_a_connected_port()
      :ok = KinoWebSerial.subscribe(port)

      when_the_port_disconnects(port)
      assert_receive {:kino_web_serial, :disconnected, ^port}

      when_the_user_connects(port)
      when_the_port_receives(port, "hello")
      refute_receive {:kino_web_serial, :data, _, _}
    end
  end

  describe "the control signals of a port" do
    @describetag spec: "API-4"

    test "can be set" do
      %{port: port} = given_a_connected_port()

      assert KinoWebSerial.set_signals(port, data_terminal_ready: false, request_to_send: true) ==
               :ok

      request = assert_browser_request(:set_signals)
      assert request.signals == %{data_terminal_ready: false, request_to_send: true}
    end

    test "can send a break" do
      %{port: port} = given_a_connected_port()

      assert KinoWebSerial.set_signals(port, break: true) == :ok

      assert %{signals: %{break: true}} = assert_browser_request(:set_signals)
    end

    test "are checked before they are sent" do
      %{port: port} = given_a_connected_port()

      assert_raise ArgumentError, ~r/unknown signals/, fn ->
        KinoWebSerial.set_signals(port, dtr: true)
      end
    end

    test "can be read" do
      signals = %{
        clear_to_send: true,
        data_set_ready: true,
        data_carrier_detect: false,
        ring_indicator: false
      }

      %{port: port} = given_a_connected_port(get_signals: {:ok, signals})

      assert KinoWebSerial.signals(port) == {:ok, signals}
      assert_browser_request(:get_signals)
    end

    test "return the error reported by the browser" do
      %{port: port} = given_a_connected_port(set_signals: {:error, "Failed to set signals."})

      assert KinoWebSerial.set_signals(port, break: false) == {:error, "Failed to set signals."}
    end
  end

  describe "streaming from a port" do
    @describetag spec: "API-5"

    test "emits the received chunks until the port disconnects" do
      %{port: port} = given_a_connected_port()

      streaming = Task.async(fn -> port |> KinoWebSerial.stream() |> Enum.to_list() end)
      await_subscribed(port)

      when_the_port_receives(port, "hello ")
      when_the_port_receives(port, "world")
      when_the_port_disconnects(port)

      assert Task.await(streaming) == ["hello ", "world"]
    end

    test "emits whole lines, without their line endings" do
      %{port: port} = given_a_connected_port()

      streaming = Task.async(fn -> port |> KinoWebSerial.lines() |> Enum.to_list() end)
      await_subscribed(port)

      when_the_port_receives(port, "temp=2")
      when_the_port_receives(port, "1.5\r\nhum")
      when_the_port_receives(port, "idity=40\n\nrest")
      when_the_port_disconnects(port)

      assert Task.await(streaming) == ["temp=21.5", "humidity=40", "", "rest"]
    end

    test "unsubscribes when the consumer stops early" do
      %{port: port} = given_a_connected_port()

      taking = Task.async(fn -> port |> KinoWebSerial.lines() |> Enum.take(1) end)
      await_subscribed(port)
      when_the_port_receives(port, "one\ntwo\n")

      assert Task.await(taking) == ["one"]
      assert subscriber_count(port) == 0
    end

    test "cannot start when the port is not connected" do
      %{port: port} = given_a_port()

      assert_raise ArgumentError, ~r/not_connected/, fn ->
        port |> KinoWebSerial.stream() |> Enum.take(1)
      end
    end
  end

  defp await_subscribed(port) do
    Stream.repeatedly(fn -> subscriber_count(port) end)
    |> Enum.find(fn count -> count > 0 || Process.sleep(5) end)
  end

  defp subscriber_count(port) do
    port
    |> KinoWebSerial.Port.whereis()
    |> :sys.get_state()
    |> Map.fetch!(:subscribers)
    |> map_size()
  end
end
