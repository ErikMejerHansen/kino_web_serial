defmodule KinoWebSerial.SpecFormatter do
  @moduledoc """
  ExUnit formatter that collects test results per requirement ID and
  writes `spec/STATUS.md` when the suite finishes.

  Used by `mix spec`, see `KinoWebSerial.Spec`.
  """

  use GenServer

  alias KinoWebSerial.Spec

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{} = test}, results) do
    result =
      case test.state do
        nil -> :passed
        {:failed, _} -> :failed
        {:invalid, _} -> :failed
        _excluded_or_skipped -> :skipped
      end

    results =
      test.tags
      |> Map.get(:spec, [])
      |> List.wrap()
      |> Enum.reduce(results, fn id, results ->
        Map.update(results, id, [result], &[result | &1])
      end)

    {:noreply, results}
  end

  def handle_cast({:suite_finished, _times}, results) do
    requirements = Spec.requirements()
    reviews = Spec.reviews()
    statuses = Spec.status(requirements, results, reviews)
    unknown_ids = Spec.unknown_ids(requirements, results, reviews)

    File.write!(Spec.status_path(), Spec.render(statuses, unknown_ids))

    counts = Enum.frequencies_by(statuses, & &1.status)

    IO.puts("""

    Spec: #{counts[:tested] || 0} tested, #{counts[:reviewed] || 0} reviewed, \
    #{counts[:failing] || 0} failing, #{counts[:open] || 0} open. See #{Spec.status_path()}\
    """)

    for %{status: status, id: id, text: text} <- statuses, status in [:failing, :open] do
      IO.puts("  #{status}: [#{id}] #{text}")
    end

    if unknown_ids != [], do: IO.puts("  unknown IDs: #{Enum.join(unknown_ids, ", ")}")

    {:noreply, results}
  end

  def handle_cast(_event, results), do: {:noreply, results}
end
