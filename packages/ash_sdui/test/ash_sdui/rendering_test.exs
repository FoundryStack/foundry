defmodule AshSDUI.RenderingTest do
  use ExUnit.Case, async: false

  alias AshSDUI.Renderer
  alias AshSDUI.Renderer.TreeNode

  setup do
    AshSDUI.Cache.start_link()
    AshSDUI.Test.TestLayout.init_layouts()
    :ok
  end

  describe "to_tree/1 with code-based layout" do
    test "returns nested TreeNode struct for known layout" do
      assert {:ok, %TreeNode{} = root} = Renderer.to_tree("test-dashboard")
      assert root.component_name == "Layouts.TwoColumn@v1"
    end

    test "root node has children" do
      {:ok, root} = Renderer.to_tree("test-dashboard")
      assert length(root.children) == 2
    end

    test "child nodes have correct component names" do
      {:ok, root} = Renderer.to_tree("test-dashboard")
      components = Enum.map(root.children, & &1.component_name)
      assert "UserProfile.Header@v1" in components
      assert "Betting.ActiveBets@v1" in components
    end

    test "children are sorted by order" do
      {:ok, root} = Renderer.to_tree("test-dashboard")
      orders = Enum.map(root.children, & &1.order)
      assert orders == Enum.sort(orders)
    end

    test "returns error for unknown layout" do
      assert {:error, {:not_found, "nonexistent"}} = Renderer.to_tree("nonexistent")
    end
  end

  describe "to_tree/1 with flat record list" do
    test "builds tree from records with parent-child structure" do
      records = [
        %{id: "root", component_name: "Root@v1", parent_id: nil, region: :default, order: 0,
          static_props: %{}, subject_resource: nil, subject_id: nil},
        %{id: "child1", component_name: "Child@v1", parent_id: "root", region: :main, order: 0,
          static_props: %{}, subject_resource: nil, subject_id: nil}
      ]

      assert {:ok, %TreeNode{} = root} = Renderer.to_tree(records)
      assert root.id == "root"
      assert length(root.children) == 1
      assert hd(root.children).id == "child1"
    end

    test "returns error when no root node found" do
      records = [
        %{id: "child1", component_name: "Child@v1", parent_id: "missing", region: :main, order: 0,
          static_props: %{}, subject_resource: nil, subject_id: nil}
      ]

      assert {:error, :no_root_node} = Renderer.to_tree(records)
    end
  end
end
