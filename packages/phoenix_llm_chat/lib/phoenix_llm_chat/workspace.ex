defmodule PhoenixLLMChat.Workspace do
  @moduledoc """
  Multi-tab session management for chat workspace.

  Handles:
  - Creating new sessions
  - Switching between tabs
  - Renaming sessions
  - Deleting sessions
  - Loading/saving session state to storage backend
  """

  import Phoenix.Component, only: [assign: 3]
  require Logger

  def hydrate_workspace(socket, session_store_impl) do
    case apply(session_store_impl, :list, []) do
      {:ok, session_ids} ->
        sessions_by_id =
          Enum.reduce(session_ids, %{}, fn sid, acc ->
            case apply(session_store_impl, :load, [sid]) do
              {:ok, data} -> Map.put(acc, sid, data)
              {:error, _} -> acc
            end
          end)

        socket
        |> assign(:sessions_by_id, sessions_by_id)
        |> assign(:open_session_ids, session_ids)

      {:error, reason} ->
        Logger.error("Failed to hydrate workspace: #{inspect(reason)}")
        socket
        |> assign(:sessions_by_id, %{})
        |> assign(:open_session_ids, [])
    end
  end

  def create_session(socket, session_id, initial_data \\ %{}) do
    sessions_by_id = socket.assigns[:sessions_by_id] || %{}
    open_session_ids = socket.assigns[:open_session_ids] || []

    if Map.has_key?(sessions_by_id, session_id) do
      socket
    else
      new_session_data = %{"messages" => [], "metadata" => %{}} |> Map.merge(initial_data)

      socket
      |> assign(:sessions_by_id, Map.put(sessions_by_id, session_id, new_session_data))
      |> assign(:open_session_ids, [session_id | open_session_ids])
    end
  end

  def open_session(socket, session_id) do
    sessions_by_id = socket.assigns[:sessions_by_id] || %{}

    case Map.fetch(sessions_by_id, session_id) do
      {:ok, session_data} ->
        socket
        |> assign(:active_session_id, session_id)
        |> assign(:messages, session_data["messages"] || [])

      :error ->
        Logger.warning("Session not found: #{session_id}")
        socket
    end
  end

  def switch_session(socket, session_id) do
    # Save current session first, then switch
    socket
    |> maybe_save_active_session()
    |> open_session(session_id)
    |> push_workspace_state()
  end

  def rename_session(socket, session_id, new_name) do
    sessions_by_id = socket.assigns[:sessions_by_id] || %{}

    updated_session = sessions_by_id
      |> Map.get(session_id, %{})
      |> Map.put("name", new_name)

    socket
    |> assign(:sessions_by_id, Map.put(sessions_by_id, session_id, updated_session))
    |> push_workspace_state()
  end

  def delete_session(socket, session_id, session_store_impl) do
    sessions_by_id = socket.assigns[:sessions_by_id] || %{}
    open_session_ids = socket.assigns[:open_session_ids] || []
    active_session_id = socket.assigns[:active_session_id]

    apply(session_store_impl, :delete, [session_id])

    updated_socket = socket
      |> assign(:sessions_by_id, Map.delete(sessions_by_id, session_id))
      |> assign(:open_session_ids, List.delete(open_session_ids, session_id))

    # Switch to another session if we deleted the active one
    if active_session_id == session_id do
      case List.first(updated_socket.assigns[:open_session_ids]) do
        nil -> updated_socket
        new_active_id -> open_session(updated_socket, new_active_id)
      end
    else
      updated_socket
    end
    |> push_workspace_state()
  end

  def push_workspace_state(socket) do
    sessions_list = build_sessions_list(socket.assigns[:sessions_by_id] || %{})

    Phoenix.LiveView.push_event(socket, "workspace_state", %{
      sessions: sessions_list,
      active_session_id: socket.assigns[:active_session_id]
    })
  end

  defp maybe_save_active_session(socket) do
    case socket.assigns[:active_session_id] do
      nil ->
        socket

      session_id ->
        sessions_by_id = socket.assigns[:sessions_by_id] || %{}
        current_session = Map.get(sessions_by_id, session_id, %{})

        updated_session = current_session
          |> Map.put("messages", socket.assigns[:messages] || [])
          |> Map.put("updated_at", DateTime.utc_now())

        assign(socket, :sessions_by_id, Map.put(sessions_by_id, session_id, updated_session))
    end
  end

  defp build_sessions_list(sessions_by_id) do
    Enum.map(sessions_by_id, fn {id, data} ->
      %{
        id: id,
        name: data["name"] || "Session",
        message_count: length(data["messages"] || []),
        updated_at: data["updated_at"]
      }
    end)
  end
end
