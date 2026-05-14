defmodule AshSDUI.LayoutTest do
  use ExUnit.Case, async: false

  alias AshSDUI.Layout

  setup_all do
    AshSDUI.Test.TestLayout.init_layouts()
    :ok
  end

  describe "code-based layout registration" do
    test "layout is registered and retrievable" do
      assert {:ok, layout} = Layout.get("test-dashboard")
      assert layout.name == "test-dashboard"
    end

    test "missing layout returns error" do
      assert {:error, :not_found} = Layout.get("nonexistent-layout")
    end

    test "root node has correct component" do
      {:ok, layout} = Layout.get("test-dashboard")
      assert layout.root.component == "Layouts.TwoColumn@v1"
    end

    test "nested nodes produce correct parent-child relationships" do
      {:ok, layout} = Layout.get("test-dashboard")
      root = layout.root
      assert length(root.children) == 2
      child_ids = Enum.map(root.children, & &1.id)
      assert :header in child_ids
      assert :body in child_ids
    end

    test "region and order options are preserved" do
      {:ok, layout} = Layout.get("test-dashboard")
      header = Enum.find(layout.root.children, &(&1.id == :header))
      assert header.region == :sidebar
      assert header.order == 0
    end

    test "all/0 returns registered layouts" do
      names = Layout.all() |> Enum.map(& &1.name)
      assert "test-dashboard" in names
    end
  end
end
