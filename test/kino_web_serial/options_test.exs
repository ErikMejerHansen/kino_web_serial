defmodule KinoWebSerial.OptionsTest do
  use ExUnit.Case, async: true

  alias KinoWebSerial.Options

  doctest Options

  describe "casting options" do
    test "accepts any positive baud rate" do
      assert Options.cast(:baud_rate, 74_880) == {:ok, 74_880}
      assert Options.cast(:baud_rate, "0") == :error
      assert Options.cast(:baud_rate, "9600 baud") == :error
    end

    test "accepts only the data bits, stop bits, parity and flow control browsers support" do
      assert Options.cast(:data_bits, 7) == {:ok, 7}
      assert Options.cast(:data_bits, "5") == :error
      assert Options.cast(:stop_bits, "2") == {:ok, 2}
      assert Options.cast(:stop_bits, 1.5) == :error
      assert Options.cast(:flow_control, "hardware") == {:ok, "hardware"}
      assert Options.cast(:flow_control, "xon/xoff") == :error
    end

    test "accepts USB IDs as up to four hex digits" do
      assert Options.cast(:usb_vendor_id, " 0x2341 ") == {:ok, "0x2341"}
      assert Options.cast(:usb_vendor_id, "") == {:ok, ""}
      assert Options.cast(:usb_vendor_id, "12345") == :error
      assert Options.cast(:usb_vendor_id, nil) == :error
    end

    test "rejects unknown fields" do
      assert Options.cast(:buffer_size, 255) == :error
    end
  end

  describe "port filters" do
    test "need a vendor ID" do
      assert Options.filters(%{usb_vendor_id: "", usb_product_id: "0043"}) == []
    end
  end
end
