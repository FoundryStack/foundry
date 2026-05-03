defmodule AshSDUI.Components.SDUIRoot do
  @moduledoc false
  use Phoenix.Component

  def render(%{tree: nil} = assigns) do
    ~H"""
    <div class="sdui-error">UI graph not found.</div>
    """
  end

  def render(%{tree: tree} = assigns) do
    assigns = assign(assigns, :node, tree)

    ~H"""
    <.render_node node={@node} />
    """
  end

  defp render_node(%{node: nil} = assigns), do: ~H""

  defp render_node(%{node: node} = assigns) do
    {module, subject} = resolve_component(node)
    children_by_region = pre_render_children(node.children || [])

    assigns =
      assigns
      |> assign(:node, node)
      |> assign(:component_module, module)
      |> assign(:subject, subject)
      |> assign(:children_by_region, children_by_region)

    ~H"""
    <%= if @component_module do %>
      <%= render_component(@component_module, @subject, @node.static_props, @node.region, @children_by_region) %>
    <% else %>
      <div
        data-sdui-component={@node.component_name}
        data-sdui-region={@node.region}
      >
        <%= for child <- (@node.children || []) do %>
          <.render_node node={child} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp render_component(module, subject, props, region, children) do
    # Create a proper assigns map for Phoenix components
    assigns = %{
      subject: subject,
      props: props,
      region: region,
      children: children,
      __changed__: nil
    }

    case module.render(assigns) do
      result when is_binary(result) -> Phoenix.HTML.raw(result)
      result -> result
    end
  end

  defp resolve_component(node) do
    case AshSDUI.Registry.lookup(node.component_name) do
      {:ok, entry} ->
        subject = AshSDUI.Calculations.ResolveSubject.resolve(node)
        {entry.module, subject}

      {:error, :not_found} ->
        {nil, nil}
    end
  end

  defp pre_render_children(children) do
    children
    |> Enum.group_by(& &1.region)
    |> Map.new(fn {region, nodes} ->
      rendered =
        nodes
        |> Enum.sort_by(& &1.order)
        |> Enum.map(&render_child_node/1)

      {region, rendered}
    end)
  end

  # Render a child node outside of HEEx context (returns rendered content)
  defp render_child_node(node) do
    {module, subject} = resolve_component(node)
    children_by_region = pre_render_children(node.children || [])

    if module do
      module.render(%{
        subject: subject,
        props: node.static_props,
        region: node.region,
        children: children_by_region
      })
    else
      # Return placeholder HTML for unregistered components
      html_placeholder(node)
    end
  end

  # Return placeholder as safe HTML string (not HEEx)
  defp html_placeholder(node) do
    children_html =
      (node.children || [])
      |> Enum.sort_by(& &1.order)
      |> Enum.map(&render_child_node/1)
      |> Enum.join("")

    ~s"""
    <div data-sdui-component="#{node.component_name}" data-sdui-region="#{node.region}">
    #{children_html}
    </div>
    """
    |> Phoenix.HTML.raw()
  end
end
