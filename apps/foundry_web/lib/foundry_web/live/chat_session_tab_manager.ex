defmodule FoundryWeb.ChatSessionTabManager do
  @moduledoc """
  Multi-tab session management for chat workspace.

  Handles switching between sessions, opening/closing tabs, persisting and restoring
  per-session state, and managing background sessions that run concurrently.
  """

  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  require Logger

  alias Foundry.Chat.FileSessionStore
  alias FoundryWeb.ChatModelCatalog

  @doc """
  Saves the active session state to per_session_state for later restoration.
  """
  def save_active_session_state(socket) do
    current_session_id = socket.assigns.active_session_id

    if current_session_id && current_session_id in socket.assigns.open_session_ids do
      state = %{
        messages: socket.assigns.messages,
        chat_loading: socket.assigns.chat_loading,
        active_request_ref: socket.assigns.active_request_ref,
        active_request_task: socket.assigns.active_request_task,
        pending_messages: socket.assigns.pending_messages,
        session_digest: socket.assigns.session_digest,
        activity_runs: socket.assigns.activity_runs,
        selected_activity_run_id: socket.assigns.selected_activity_run_id,
        error: socket.assigns.error
      }

      input = socket.assigns.input || ""

      socket
      |> update(:per_session_state, &Map.put(&1, current_session_id, state))
      |> update(:session_inputs, &Map.put(&1, current_session_id, input))
    else
      socket
    end
  end

  @doc """
  Restores session state from per_session_state or loads from file.
  """
  def restore_session_state(socket, nil), do: socket

  def restore_session_state(socket, session_id) do
    case Map.get(socket.assigns.per_session_state, session_id) do
      # Active stream exists for this session
      state when is_map(state) ->
        input = Map.get(socket.assigns.session_inputs, session_id, "")

        # Verify the task is still alive before restoring active request refs
        task_alive? =
          is_map(state.active_request_task) &&
            is_pid(state.active_request_task[:pid]) &&
            Process.alive?(state.active_request_task[:pid])

        socket
        |> assign(:session_id, session_id)
        |> assign(:messages, state.messages)
        |> assign(:chat_loading, if(task_alive?, do: state.chat_loading, else: false))
        |> assign(:active_request_ref, if(task_alive?, do: state.active_request_ref, else: nil))
        |> assign(:active_request_task, if(task_alive?, do: state.active_request_task, else: nil))
        |> assign(:pending_messages, state.pending_messages)
        |> assign(:session_digest, state.session_digest)
        |> assign(:activity_runs, state.activity_runs)
        |> assign(:selected_activity_run_id, state.selected_activity_run_id)
        |> assign(:error, state.error)
        |> assign(:input, input)

      # No active stream, load from file
      nil ->
        input = Map.get(socket.assigns.session_inputs, session_id, "")

        socket
        |> maybe_load_active_session_into_chat(session_id)
        |> assign(:input, input)
    end
  end

  @doc """
  Switches to a different session: saves current, then restores target.
  """
  def switch_to_session(socket, session_id) do
    socket
    |> save_active_session_state()
    |> restore_session_state(session_id)
  end

  @doc """
  Pushes current workspace state to frontend.
  """
  def push_workspace_state(socket) do
    push_event(socket, "workspace:state", %{
      workspace_id: socket.assigns.workspace_id,
      active_session_id: socket.assigns.active_session_id,
      open_session_ids: socket.assigns.open_session_ids,
      session_count: map_size(socket.assigns.sessions_by_id || %{})
    })
  end

  @doc """
  Lists persisted sessions in a workspace.
  """
  def list_persisted_sessions(workspace_id, project_fingerprint) do
    with {:ok, sessions} <- FileSessionStore.list(workspace_id, project_fingerprint) do
      Map.new(sessions, &{&1["id"], &1})
    else
      _ -> %{}
    end
  end

  @doc """
  Creates a new session in the workspace.
  """
  def create_session_in_workspace(socket, workspace_id) do
    session_id = Ecto.UUID.generate()

    case FileSessionStore.create(%{
           id: session_id,
           workspace_id: workspace_id,
           project_fingerprint: socket.assigns.project_fingerprint,
           title: "New session",
           selected_model_id: socket.assigns.selected_model && socket.assigns.selected_model.id,
           selected_provider:
             socket.assigns.selected_model && to_string(socket.assigns.selected_model.provider),
           model: socket.assigns.selected_model && socket.assigns.selected_model.model_id
         }) do
      {:ok, session} ->
        open_ids = [session_id | socket.assigns.open_session_ids]
        sessions_by_id = Map.put(socket.assigns.sessions_by_id, session_id, session)
        {socket, open_ids, sessions_by_id, session_id}

      {:error, _reason} ->
        {socket, socket.assigns.open_session_ids, socket.assigns.sessions_by_id,
         socket.assigns.active_session_id}
    end
  end

  @doc """
  Updates state of a background session (one not currently active).
  """
  def update_background_session(socket, request_ref, fun) do
    update(socket, :per_session_state, fn states ->
      Enum.reduce(states, states, fn {session_id, state}, acc ->
        if state.active_request_ref == request_ref do
          Map.put(acc, session_id, fun.(state))
        else
          acc
        end
      end)
    end)
  end

  @doc """
  Finds the session containing a given request_ref.
  """
  def find_background_session_for_request(per_session_state, request_ref) do
    Enum.find_value(per_session_state, fn {session_id, state} ->
      if state.active_request_ref == request_ref, do: {session_id, state}, else: nil
    end)
  end

  @doc """
  Persists a background session to file.
  """
  def save_background_session_to_file(session_id, state, socket) do
    Task.Supervisor.async_nolink(FoundryWeb.ChatTaskSupervisor, fn ->
      FoundryWeb.ChatSessionDomainLogic.save_session_state(
        session_id,
        state.messages,
        state.session_digest,
        socket.assigns.workspace_id,
        socket.assigns.project_fingerprint,
        socket.assigns.selected_model
      )
    end)
  end

  @doc """
  Resolves a selected model from the catalog, defaulting if not found.
  """
  def resolve_selected_model(nil, model_catalog) do
    ChatModelCatalog.get(model_catalog, ChatModelCatalog.default_model_id(model_catalog))
  end

  def resolve_selected_model(model_id, model_catalog) do
    ChatModelCatalog.get(model_catalog, model_id) ||
      ChatModelCatalog.get(model_catalog, ChatModelCatalog.default_model_id(model_catalog))
  end

  # Private helpers

  defp maybe_load_active_session_into_chat(socket, nil), do: socket

  defp maybe_load_active_session_into_chat(socket, session_id) do
    case FoundryWeb.ChatSessionDomainLogic.load_session(session_id) do
      {:ok, session} when not is_nil(session) ->
        selected_model =
          session["selected_model_id"]
          |> resolve_selected_model(socket.assigns.model_catalog)

        socket
        |> assign(:session_id, session_id)
        |> assign(:messages, session["messages"] || [])
        |> assign(:session_digest, session["session_digest"] || %{})
        |> assign(:selected_model, selected_model)
        |> assign(:llm_provider, selected_model && selected_model.provider)
        |> assign(:llm_diagnostics, llm_diagnostics(selected_model))
        |> assign(:chat_loading, false)
        |> assign(:error, nil)
        |> assign(:active_request_ref, nil)
        |> assign(:active_request_task, nil)
        |> assign(:pending_messages, [])

      _ ->
        socket
        |> assign(:session_id, session_id)
        |> assign(:messages, [])
        |> assign(:session_digest, %{})
        |> assign(:activity_runs, [])
        |> assign(:selected_activity_run_id, nil)
        |> assign(:chat_loading, false)
        |> assign(:error, nil)
        |> assign(:active_request_ref, nil)
        |> assign(:active_request_task, nil)
        |> assign(:pending_messages, [])
    end
  end

  defp llm_diagnostics(selected_model) do
    provider = selected_model && selected_model.provider
    model = selected_model && selected_model.model_id

    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      provider: provider,
      model: model,
      node: Node.self(),
      extra: %{}
    }
  end
end
