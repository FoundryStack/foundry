defmodule FoundryWeb.SystemMapLive do
  use FoundryWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    project_root = Application.get_env(:foundry_web, :igaming_project_root,
      Path.expand("../../reference_projects/igaming", __DIR__))

    context_json = case Foundry.Context.ProjectContext.build(project_root) do
      {:ok, context} -> Jason.encode!(context)
      {:error, _reason} -> nil
    end

    {:ok, assign(socket, context_json: context_json, selected_node: nil, project_root: project_root)}
  end

  @impl true
  def handle_event("node_selected", %{"id" => _id, "data" => node_data}, socket) do
    {:noreply, assign(socket, selected_node: node_data)}
  end

  @impl true
  def handle_event("fetch_node_detail", %{"id" => module_id}, socket) do
    # Above 200-module threshold path
    project_root = socket.assigns.project_root
    case Foundry.Context.ProjectContext.build_one(project_root, module_id) do
      {:ok, node} ->
        {:noreply, push_event(socket, "node_detail", %{node: node})}
      {:error, _} ->
        {:noreply, socket}
    end
  end
end
