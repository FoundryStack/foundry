defmodule AshSDUI.Renderer do
  @moduledoc """
  Converts a UI graph (from DB records or code-based layouts) into a nested
  tree of `%AshSDUI.Renderer.TreeNode{}` structs ready for rendering.
  """

  defmodule TreeNode do
    @moduledoc false
    defstruct [:id, :component_name, :static_props, :subject_resource, :subject_id, :region, :order, :children]
  end

  @doc """
  Converts either a list of UINode records or a layout name string into a
  nested TreeNode struct suitable for rendering.
  """
  def to_tree(layout_name) when is_binary(layout_name) do
    case AshSDUI.Cache.get(layout_name) do
      {:ok, tree} ->
        {:ok, tree}

      {:error, :not_found} ->
        result = build_tree(layout_name)

        case result do
          {:ok, tree} ->
            AshSDUI.Cache.put(layout_name, tree)
            {:ok, tree}

          err ->
            err
        end
    end
  end

  def to_tree(records) when is_list(records) do
    # Build tree from a flat list of UINode records
    root =
      Enum.find(records, fn r ->
        is_nil(Map.get(r, :parent_id))
      end)

    if root do
      {:ok, build_from_records(root, records)}
    else
      {:error, :no_root_node}
    end
  end

  defp build_tree(layout_name) do
    case AshSDUI.Layout.get(layout_name) do
      {:ok, layout_def} ->
        {:ok, layout_node_to_tree(layout_def.root)}

      {:error, :not_found} ->
        {:error, {:not_found, layout_name}}
    end
  end


  defp build_from_records(node, all_records) do
    children =
      all_records
      |> Enum.filter(&(Map.get(&1, :parent_id) == node.id))
      |> Enum.sort_by(& &1.order)
      |> Enum.map(&build_from_records(&1, all_records))

    %TreeNode{
      id: node.id,
      component_name: node.component_name,
      static_props: node.static_props,
      subject_resource: node.subject_resource,
      subject_id: node.subject_id,
      region: node.region,
      order: node.order,
      children: children
    }
  end

  defp layout_node_to_tree(nil), do: nil

  defp layout_node_to_tree(%AshSDUI.Layout.Node{} = node) do
    children =
      (node.children || [])
      |> Enum.sort_by(& &1.order)
      |> Enum.map(&layout_node_to_tree/1)

    %TreeNode{
      id: node.id,
      component_name: node.component,
      static_props: %{},
      subject_resource: node.subject_resource,
      subject_id: node.subject_id,
      region: node.region,
      order: node.order,
      children: children
    }
  end
end
