defmodule KinoWebSerial.Options do
  @moduledoc """
  The options a serial port is opened with, as entered in the Smart Cell.

    * `:baud_rate` - bits per second, defaults to `115200`
    * `:data_bits` - `7` or `8` (default)
    * `:parity` - `"none"` (default), `"even"` or `"odd"`
    * `:stop_bits` - `1` (default) or `2`
    * `:flow_control` - `"none"` (default) or `"hardware"`

  The port selector can be limited to USB devices with a given vendor
  and product ID, entered as hex:

      iex> KinoWebSerial.Options.filters(%{usb_vendor_id: "2341", usb_product_id: "0x0043"})
      [%{usbVendorId: 0x2341, usbProductId: 0x0043}]

      iex> KinoWebSerial.Options.filters(%{usb_vendor_id: "", usb_product_id: ""})
      []

  """

  @type t :: %{
          baud_rate: pos_integer(),
          data_bits: 7 | 8,
          parity: String.t(),
          stop_bits: 1 | 2,
          flow_control: String.t()
        }

  @defaults %{
    baud_rate: 115_200,
    data_bits: 8,
    parity: "none",
    stop_bits: 1,
    flow_control: "none",
    usb_vendor_id: "",
    usb_product_id: ""
  }

  @choices %{
    baud_rate: [
      300,
      1200,
      2400,
      4800,
      9600,
      19200,
      38400,
      57600,
      115_200,
      230_400,
      460_800,
      921_600,
      1_000_000,
      2_000_000
    ],
    data_bits: [7, 8],
    parity: ["none", "even", "odd"],
    stop_bits: [1, 2],
    flow_control: ["none", "hardware"]
  }

  @doc "The fields and their default values."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc """
  The values offered in the Smart Cell for each option.

  Any positive baud rate is accepted, the list holds the common ones.
  """
  @spec choices() :: map()
  def choices, do: @choices

  @doc "The fields that are passed to the browser when opening the port."
  @spec open_fields() :: [atom()]
  def open_fields, do: [:baud_rate, :data_bits, :parity, :stop_bits, :flow_control]

  @doc """
  Casts a value entered in the Smart Cell for the given field.

      iex> KinoWebSerial.Options.cast(:baud_rate, "9600")
      {:ok, 9600}

      iex> KinoWebSerial.Options.cast(:parity, "mark")
      :error

  """
  @spec cast(atom(), term()) :: {:ok, term()} | :error
  def cast(:baud_rate, value) do
    case integer(value) do
      {:ok, rate} when rate > 0 -> {:ok, rate}
      _other -> :error
    end
  end

  def cast(field, value) when field in [:data_bits, :stop_bits] do
    with {:ok, int} <- integer(value), true <- int in @choices[field] do
      {:ok, int}
    else
      _ -> :error
    end
  end

  def cast(field, value) when field in [:parity, :flow_control] do
    if value in @choices[field], do: {:ok, value}, else: :error
  end

  def cast(field, value) when field in [:usb_vendor_id, :usb_product_id] and is_binary(value) do
    value = String.trim(value)

    case value do
      "" -> {:ok, ""}
      _ -> with {:ok, _id} <- usb_id(value), do: {:ok, value}
    end
  end

  def cast(_field, _value), do: :error

  @doc """
  Returns the port filters for the browser's port selector.
  """
  @spec filters(map()) :: [map()]
  def filters(fields) do
    case {usb_id(fields.usb_vendor_id), usb_id(fields.usb_product_id)} do
      {{:ok, vendor}, {:ok, product}} -> [%{usbVendorId: vendor, usbProductId: product}]
      {{:ok, vendor}, _product} -> [%{usbVendorId: vendor}]
      _no_vendor -> []
    end
  end

  @doc """
  Formats a USB vendor or product ID as four hex digits.

      iex> KinoWebSerial.Options.format_usb_id(0x2341)
      "2341"

  """
  @spec format_usb_id(non_neg_integer() | nil) :: String.t() | nil
  def format_usb_id(nil), do: nil

  def format_usb_id(id) when is_integer(id) do
    id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")
  end

  defp usb_id(value) when is_binary(value) do
    hex = value |> String.trim() |> String.downcase() |> String.replace_prefix("0x", "")

    if Regex.match?(~r/^[0-9a-f]{1,4}$/, hex),
      do: {:ok, String.to_integer(hex, 16)},
      else: :error
  end

  defp usb_id(_value), do: :error

  defp integer(value) when is_integer(value), do: {:ok, value}

  defp integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _other -> :error
    end
  end

  defp integer(_value), do: :error
end
