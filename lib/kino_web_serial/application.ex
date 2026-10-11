defmodule KinoWebSerial.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Kino.SmartCell.register(KinoWebSerial.SmartCell)

    children = [
      {Registry, keys: :unique, name: KinoWebSerial.Registry}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: KinoWebSerial.Supervisor)
  end
end
