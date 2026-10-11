defmodule KinoWebSerial.ValueTest do
  use ExUnit.Case, async: true

  alias KinoWebSerial.Value

  doctest Value

  describe "parsing hex input" do
    test "ignores separators and 0x prefixes" do
      assert Value.parse("0x01:02, 03 0x04", "hex") == {:ok, <<1, 2, 3, 4>>}
    end

    test "rejects odd or non-hex input" do
      assert Value.parse("abc", "hex") == {:error, "invalid hex value"}
      assert Value.parse("zz", "hex") == {:error, "invalid hex value"}
    end
  end

  test "rejects unknown formats and line endings" do
    assert Value.parse("1", "base64") == {:error, ~s(unknown format "base64")}
    assert Value.line_ending("lfcr") == {:error, ~s(unknown line ending "lfcr")}
  end

  describe "line endings" do
    test "are added as bytes" do
      assert Value.line_ending("none") == {:ok, ""}
      assert Value.line_ending("lf") == {:ok, "\n"}
      assert Value.line_ending("cr") == {:ok, "\r"}
      assert Value.line_ending("crlf") == {:ok, "\r\n"}
    end

    test "are trimmed once" do
      assert Value.trim_line_ending("a\r\r\n") == "a\r"
      assert Value.trim_line_ending("a\n\n") == "a\n"
      assert Value.trim_line_ending("a\r") == "a\r"
    end
  end

  describe "displaying data" do
    test "keeps printable text, including unicode" do
      assert Value.to_text("héllo ✓") == "héllo ✓"
    end

    test "escapes control characters, backslashes and invalid UTF-8" do
      assert Value.to_text(<<"a\\b", 0x1B, "[0m", 0xC3>>) == "a\\\\b\\x1b[0m\\xc3"
    end

    test "shows an empty value as empty strings" do
      assert Value.to_hex("") == ""
      assert Value.to_text("") == ""
    end
  end
end
