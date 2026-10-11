defmodule KinoWebSerial.SpecTest do
  use ExUnit.Case, async: true

  alias KinoWebSerial.Spec

  describe "the spec" do
    test "has requirements with unique IDs" do
      requirements = Spec.requirements()

      assert %{id: "ARCH-1", section: "Architecture"} = hd(requirements)
      assert Enum.all?(requirements, &(&1.text =~ "shall"))
    end

    test "has reviews only for requirements it contains" do
      assert Spec.unknown_ids(Spec.requirements(), %{}, Spec.reviews()) == []
    end
  end

  describe "the status of a requirement" do
    setup do
      %{requirement: %{id: "UI-1", section: "UI", text: "The UI shall work"}}
    end

    test "is tested when all its tests pass", %{requirement: requirement} do
      assert [%{status: :tested, tests: 2}] =
               Spec.status([requirement], %{"UI-1" => [:passed, :passed]}, %{})
    end

    test "is failing when any of its tests fail, even if reviewed", %{requirement: requirement} do
      assert [%{status: :failing}] =
               Spec.status([requirement], %{"UI-1" => [:passed, :failed]}, %{"UI-1" => "ok"})
    end

    test "is reviewed when it has a review but no tests", %{requirement: requirement} do
      assert [%{status: :reviewed, review: "ok"}] =
               Spec.status([requirement], %{}, %{"UI-1" => "ok"})
    end

    test "is open without tests or review", %{requirement: requirement} do
      assert [%{status: :open}] = Spec.status([requirement], %{"UI-1" => [:skipped]}, %{})
    end
  end

  test "IDs used by tests but missing from the spec are reported" do
    requirements = [%{id: "UI-1", section: "UI", text: "The UI shall work"}]

    assert Spec.unknown_ids(requirements, %{"UI-1" => [], "UI-9" => []}, %{"OLD-1" => "x"}) ==
             ["OLD-1", "UI-9"]
  end
end
