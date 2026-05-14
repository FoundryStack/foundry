defmodule AshSDUI.RegistryTest do
  use ExUnit.Case, async: false

  alias AshSDUI.Registry

  setup do
    # Clean the registry before each test by overwriting with empty map
    :persistent_term.put({Registry, :components}, %{})
    :ok
  end

  test "register and lookup a component" do
    Registry.register("UserProfile.Header@v1", FakeModule, %{fragment: "fragment X on User { id }"})

    assert {:ok, entry} = Registry.lookup("UserProfile.Header@v1")
    assert entry.module == FakeModule
    assert entry.name == "UserProfile.Header@v1"
  end

  test "lookup returns error for missing key" do
    assert {:error, :not_found} = Registry.lookup("Missing.Component@v1")
  end

  test "all/0 returns all registered components" do
    Registry.register("Comp.A@v1", ModA, %{fragment: "fragment A on User { id }"})
    Registry.register("Comp.B@v1", ModB, %{fragment: "fragment B on Player { id }"})

    names = Registry.all() |> Enum.map(& &1.name)
    assert "Comp.A@v1" in names
    assert "Comp.B@v1" in names
  end

  test "overwriting a key with same name updates the entry" do
    Registry.register("Comp.X@v1", ModOld, %{})
    Registry.register("Comp.X@v1", ModNew, %{})

    assert {:ok, entry} = Registry.lookup("Comp.X@v1")
    assert entry.module == ModNew
  end
end
