defmodule KinoWebSerial.Log do
  @moduledoc """
  The data sent and received, as shown in the Smart Cell.

  Serial data arrives in chunks of arbitrary size, so received data is
  joined and split into lines, like a serial monitor does. A line ends
  with `\\n` or after 1024 bytes. Data sent and errors get an entry each.

  Only the newest entries are kept.
  """

  @max_line_bytes 1024

  defstruct entries: [], next_id: 1, max_entries: 200

  @type direction :: :rx | :tx | :error

  @type entry :: %{
          id: pos_integer(),
          direction: direction(),
          at: integer(),
          data: binary(),
          open: boolean()
        }

  @type t :: %__MODULE__{
          entries: [entry()],
          next_id: pos_integer(),
          max_entries: pos_integer()
        }

  @doc """
  Returns an empty log.

  ## Options

    * `:max_entries` - how many entries to keep, defaults to `200`

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct!(__MODULE__, opts)

  @doc """
  Adds data to the log, at the given time in milliseconds.

  Returns the log and the entries that were added or changed, oldest
  first.
  """
  @spec add(t(), direction(), binary(), integer()) :: {t(), [entry()]}
  def add(log, :rx, data, at) do
    case log.entries do
      [%{direction: :rx, open: true} = last | rest] ->
        put_lines(%{log | entries: rest}, last, last.data <> data)

      _other ->
        {entry, log} = new_entry(log, :rx, at)
        put_lines(log, entry, data)
    end
  end

  def add(log, direction, data, at) when direction in [:tx, :error] do
    {entry, log} = new_entry(log, direction, at)
    put_entries(log, [%{entry | data: data}])
  end

  @doc "Removes all entries."
  @spec clear(t()) :: t()
  def clear(log), do: %{log | entries: []}

  @doc "Returns the entries, oldest first."
  @spec entries(t()) :: [entry()]
  def entries(log), do: Enum.reverse(log.entries)

  defp put_lines(log, _entry, ""), do: {log, []}

  defp put_lines(log, entry, data) do
    [{first, open?} | rest] = split_lines(data)
    first = %{entry | data: first, open: open?}

    {rest, log} =
      Enum.map_reduce(rest, log, fn {line, open?}, log ->
        {entry, log} = new_entry(log, :rx, entry.at)
        {%{entry | data: line, open: open?}, log}
      end)

    put_entries(log, [first | rest])
  end

  defp put_entries(log, entries) do
    all = Enum.take(Enum.reverse(entries, log.entries), log.max_entries)
    {%{log | entries: all}, entries}
  end

  defp new_entry(log, direction, at) do
    entry = %{id: log.next_id, direction: direction, at: at, data: "", open: false}
    {entry, %{log | next_id: log.next_id + 1}}
  end

  # Splits data into {line, open?} pieces. Only the last piece can be open.
  defp split_lines(""), do: []

  defp split_lines(data) do
    cut =
      case :binary.match(data, "\n") do
        {position, _length} -> min(position + 1, @max_line_bytes)
        :nomatch when byte_size(data) > @max_line_bytes -> @max_line_bytes
        :nomatch -> nil
      end

    case cut do
      nil ->
        [{data, true}]

      cut ->
        <<line::binary-size(cut), rest::binary>> = data
        [{line, false} | split_lines(rest)]
    end
  end
end
