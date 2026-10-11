defmodule KinoWebSerial.SerialCase do
  @moduledoc """
  Given/when/then helpers for describing behaviour against a fake browser.

  The fake port is a USB device with vendor ID `2341` and product ID
  `0043`, opened at 115200 baud, 8N1.
  """

  use ExUnit.CaseTemplate

  alias KinoWebSerial.{FakeBrowser, Port}

  using do
    quote do
      import KinoWebSerial.SerialCase
    end
  end

  @options %{baud_rate: 115_200, data_bits: 8, parity: "none", stop_bits: 1, flow_control: "none"}

  @doc "The options the fake port is opened with."
  def options, do: @options

  ## Given

  @doc """
  A port in a Smart Cell, not yet connected.

  `responses` script how the browser answers operations, see
  `KinoWebSerial.FakeBrowser`.
  """
  def given_a_port(responses \\ []) do
    id = "serial-test-#{System.unique_integer([:positive])}"

    browser = start_supervised!({FakeBrowser, test: self(), port_id: id, responses: responses})
    start_supervised!({Port, id: id, bridge: browser})

    %{port: KinoWebSerial.port(id), browser: browser}
  end

  @doc "A port the user connected to in the Smart Cell."
  def given_a_connected_port(responses \\ []) do
    %{port: port} = given = given_a_port(responses)
    when_the_user_connects(port)
    given
  end

  ## When

  @doc "The user picks the port in the browser and it gets opened."
  def when_the_user_connects(port) do
    Port.connected(port, %{usb_vendor_id: 0x2341, usb_product_id: 0x0043, options: @options})
    assert_receive {:kino_web_serial, :port_changed, %{status: :connected}}
  end

  @doc "The browser loses the port, for example because it was unplugged."
  def when_the_port_disconnects(port) do
    Port.disconnected(port)
    assert_receive {:kino_web_serial, :port_changed, %{status: :disconnected}}
  end

  @doc "The browser reads data from the port."
  def when_the_port_receives(port, data) do
    Port.deliver(port.id, {:data, data})
  end

  @doc "The browser completes a request it was asked to perform."
  def when_the_browser_completes(port, request, result) do
    Port.deliver(port.id, {:response, request.ref, result})
  end

  ## Then

  @doc "Asserts the browser was asked to perform `op` and returns the request."
  defmacro assert_browser_request(op, timeout \\ 100) do
    quote do
      assert_receive {:browser_request, %{op: unquote(op)} = request}, unquote(timeout)
      request
    end
  end

  @doc "Asserts the browser was not asked to perform `op`."
  defmacro refute_browser_request(op, timeout \\ 50) do
    quote do
      refute_receive {:browser_request, %{op: unquote(op)}}, unquote(timeout)
    end
  end
end
