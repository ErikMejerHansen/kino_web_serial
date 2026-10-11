defmodule KinoWebSerial.LogTest do
  use ExUnit.Case, async: true

  alias KinoWebSerial.Log

  describe "received data" do
    test "is joined until the end of a line" do
      {log, [%{id: id, data: "he", open: true}]} = Log.add(Log.new(), :rx, "he", 1)
      {log, [%{id: ^id, data: "hello\n", open: false}]} = Log.add(log, :rx, "llo\n", 2)

      assert [%{data: "hello\n", at: 1}] = Log.entries(log)
    end

    test "is split into lines" do
      {log, changed} = Log.add(Log.new(), :rx, "one\ntwo\nthr", 1)

      assert Enum.map(changed, &{&1.data, &1.open}) == [
               {"one\n", false},
               {"two\n", false},
               {"thr", true}
             ]

      assert Log.entries(log) == changed
    end

    test "ends a line after 1024 bytes without a line ending" do
      data = String.duplicate("x", 1500)

      {_log, [first, rest]} = Log.add(Log.new(), :rx, data, 1)

      assert byte_size(first.data) == 1024 and not first.open
      assert byte_size(rest.data) == 476 and rest.open
    end

    test "starts a new line after data was sent" do
      {log, _} = Log.add(Log.new(), :rx, "prompt> ", 1)
      {log, _} = Log.add(log, :tx, "help\n", 2)
      {log, _} = Log.add(log, :rx, "usage", 3)

      assert Enum.map(Log.entries(log), & &1.direction) == [:rx, :tx, :rx]
    end
  end

  test "keeps only the newest entries" do
    log =
      Enum.reduce(1..5, Log.new(max_entries: 3), fn n, log ->
        {log, _} = Log.add(log, :tx, "#{n}", n)
        log
      end)

    assert Enum.map(Log.entries(log), & &1.data) == ["3", "4", "5"]
  end

  test "can be cleared" do
    {log, _} = Log.add(Log.new(), :error, "oops", 1)

    assert Log.entries(Log.clear(log)) == []
  end
end
