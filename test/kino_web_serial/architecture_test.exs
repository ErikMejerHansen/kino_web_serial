defmodule KinoWebSerial.ArchitectureTest do
  use KinoWebSerial.SerialCase, async: true

  alias KinoWebSerial.Port

  describe "the package" do
    @tag spec: "ARCH-1"
    test "is named kino_web_serial" do
      config = Mix.Project.config()

      assert config[:app] == :kino_web_serial
      assert config[:package][:name] in [nil, "kino_web_serial"]
    end

    @tag spec: "ARCH-2"
    test "keeps all modules in the KinoWebSerial namespace" do
      {:ok, modules} = :application.get_key(:kino_web_serial, :modules)

      for module <- modules do
        assert module == KinoWebSerial or String.starts_with?(inspect(module), "KinoWebSerial.")
      end
    end
  end

  describe "the interfaces" do
    @tag spec: "ARCH-3"
    test "include a Smart Cell registered with Livebook" do
      assert Enum.any?(
               Kino.SmartCell.definitions(),
               &match?(%{module: KinoWebSerial.SmartCell, name: "Web Serial"}, &1)
             )
    end

    @tag spec: "ARCH-4"
    test "include a documented API module" do
      assert {:docs_v1, _, :elixir, _, %{"en" => _moduledoc}, _, _} =
               Code.fetch_docs(KinoWebSerial)

      Code.ensure_loaded!(KinoWebSerial)

      for {name, arity} <- [write: 3, write_async: 2, subscribe: 1, stream: 1, set_signals: 3] do
        assert function_exported?(KinoWebSerial, name, arity)
      end
    end
  end

  describe "a port" do
    @tag spec: "ARCH-5"
    test "runs a GenServer that outlives disconnects" do
      %{port: port} = given_a_port()
      pid = Port.whereis(port)

      assert is_pid(pid)
      assert {:status, ^pid, {:module, :gen_server}, _} = :sys.get_status(pid)

      when_the_user_connects(port)
      when_the_port_disconnects(port)

      assert Port.whereis(port) == pid
    end

    @tag spec: "ARCH-5"
    test "stops with its Smart Cell" do
      %{port: port, browser: browser} = given_a_port()
      ref = Process.monitor(Port.whereis(port))

      GenServer.stop(browser)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    end
  end
end
