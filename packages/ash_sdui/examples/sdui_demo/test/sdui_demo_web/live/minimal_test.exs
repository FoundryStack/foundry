defmodule SduiDemoWeb.Live.MinimalTest do
  use ExUnit.Case, async: false

  test "persistent_term is populated with components" do
    key = {AshSDUI.Registry, :components}
    map = case :persistent_term.get(key, nil) do
      nil -> flunk("persistent_term not populated")
      m -> m
    end

    assert map_size(map) == 3
    assert "UserCard@v1" in Map.keys(map)
    assert "ActionButton@v1" in Map.keys(map)
    assert "Layouts.TwoColumnLayout@v1" in Map.keys(map)
  end

  test "registry lookup works for all components" do
    assert {:ok, _entry} = AshSDUI.Registry.lookup("UserCard@v1")
    assert {:ok, _entry} = AshSDUI.Registry.lookup("ActionButton@v1")
    assert {:ok, _entry} = AshSDUI.Registry.lookup("Layouts.TwoColumnLayout@v1")
  end
end
