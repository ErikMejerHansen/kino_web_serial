defmodule KinoWebSerial.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ErikMejerHansen/kino_web_serial"

  def project do
    [
      app: :kino_web_serial,
      version: @version,
      description: "Web Serial Smart Cell and API for Livebook",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      package: package()
    ]
  end

  def cli do
    [preferred_envs: [spec: :test]]
  end

  def application do
    [
      mod: {KinoWebSerial.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:kino, "~> 0.13"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      # Runs the tests and writes spec/STATUS.md
      spec: ["test --formatter ExUnit.CLIFormatter --formatter KinoWebSerial.SpecFormatter"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
