defmodule KinoWebSerial.Value do
  @moduledoc """
  Converts data between binaries and the textual representations used
  in the Smart Cell UI.

      iex> KinoWebSerial.Value.parse("0a FF", "hex")
      {:ok, <<10, 255>>}

      iex> KinoWebSerial.Value.parse("hi", "text")
      {:ok, "hi"}

      iex> KinoWebSerial.Value.to_hex(<<10, 255>>)
      "0a ff"

      iex> KinoWebSerial.Value.to_text("ok\\r\\n")
      "ok\\\\r\\\\n"

  """

  @formats ["text", "hex"]

  @line_endings [
    {"none", ""},
    {"lf", "\n"},
    {"cr", "\r"},
    {"crlf", "\r\n"}
  ]

  @doc "The input formats supported by `parse/2`."
  @spec formats() :: [String.t()]
  def formats, do: @formats

  @doc "The names of the line endings supported by `line_ending/1`."
  @spec line_endings() :: [String.t()]
  def line_endings, do: Enum.map(@line_endings, &elem(&1, 0))

  @doc """
  Returns the bytes of a line ending: `"none"`, `"lf"`, `"cr"` or `"crlf"`.
  """
  @spec line_ending(String.t()) :: {:ok, binary()} | {:error, String.t()}
  def line_ending(name) do
    case List.keyfind(@line_endings, name, 0) do
      {^name, bytes} -> {:ok, bytes}
      nil -> {:error, "unknown line ending #{inspect(name)}"}
    end
  end

  @doc """
  Parses user input in the given format (`"text"` or `"hex"`) into a binary.

  Hex input may contain whitespace, `:`, `,` and `0x` prefixes.
  """
  @spec parse(String.t(), String.t()) :: {:ok, binary()} | {:error, String.t()}
  def parse(input, "text") when is_binary(input), do: {:ok, input}

  def parse(input, "hex") when is_binary(input) do
    hex =
      input
      |> String.replace(~r/0x/i, "")
      |> String.replace(~r/[\s:,]/, "")

    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, "invalid hex value"}
    end
  end

  def parse(_input, format), do: {:error, "unknown format #{inspect(format)}"}

  @doc "Formats a binary as space separated, lowercase hex bytes."
  @spec to_hex(binary()) :: String.t()
  def to_hex(binary) when is_binary(binary) do
    binary
    |> Base.encode16(case: :lower)
    |> String.replace(~r/(..)(?!$)/, "\\1 ")
  end

  @doc """
  Removes one trailing line ending, `"\\n"` or `"\\r\\n"`.

      iex> KinoWebSerial.Value.trim_line_ending("ok\\r\\n")
      "ok"

  """
  @spec trim_line_ending(binary()) :: binary()
  def trim_line_ending(binary) when is_binary(binary) do
    cond do
      String.ends_with?(binary, "\r\n") -> binary_part(binary, 0, byte_size(binary) - 2)
      String.ends_with?(binary, "\n") -> binary_part(binary, 0, byte_size(binary) - 1)
      true -> binary
    end
  end

  @doc """
  Formats a binary as readable text.

  Control characters and invalid UTF-8 are escaped, like `\\r`, `\\t`
  and `\\x00`, so that nothing received is hidden.
  """
  @spec to_text(binary()) :: String.t()
  def to_text(binary) when is_binary(binary), do: escape(binary, "")

  defp escape(<<>>, acc), do: acc
  defp escape(<<?\n, rest::binary>>, acc), do: escape(rest, acc <> "\\n")
  defp escape(<<?\r, rest::binary>>, acc), do: escape(rest, acc <> "\\r")
  defp escape(<<?\t, rest::binary>>, acc), do: escape(rest, acc <> "\\t")
  defp escape(<<?\\, rest::binary>>, acc), do: escape(rest, acc <> "\\\\")

  defp escape(<<char::utf8, rest::binary>>, acc) when char >= 0x20 and char not in 0x7F..0x9F do
    escape(rest, acc <> <<char::utf8>>)
  end

  defp escape(<<byte, rest::binary>>, acc) do
    escape(rest, acc <> "\\x" <> Base.encode16(<<byte>>, case: :lower))
  end
end
