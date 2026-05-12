defmodule FoundryWeb.ChatSessionDomainLogic do
  @moduledoc """
  Foundry-specific domain logic for chat.

  Extracted from ChatSession to separate generic streaming patterns
  from Foundry-specific concerns:
  - Proposal/change management
  - Activity run tracking with ChatTrace
  - Session memory integration with SpecKit
  - Foundry retrieval context (tool results)
  - Project-specific system prompts
  """

  import Phoenix.Component, only: [assign: 3]
  require Ash.Query

  # --- Proposal / Change Management ---

  def apply_proposal(socket, _proposal_id) do
    # 100% Foundry-specific: proposal workflow
    socket
    |> assign(:proposal_id, nil)
    |> assign(:pending_proposal, nil)
  end

  def revise_proposal(socket, _proposal_id, _changes) do
    # Foundry SpecKit integration
    socket
  end

  def cancel_proposal(socket, _proposal_id) do
    socket
    |> assign(:proposal_id, nil)
  end

  # --- Activity Run Tracking ---

  def create_activity_run(socket, metadata \\ %{}) do
    run_id = Ecto.UUID.generate()

    activity_runs = socket.assigns[:activity_runs] || []
    new_run = %{
      id: run_id,
      status: :running,
      created_at: DateTime.utc_now(),
      metadata: metadata,
      trace_events: []
    }

    assign(socket, :activity_runs, [new_run | activity_runs])
  end

  def complete_activity_run(socket, run_id, result_metadata \\ %{}) do
    activity_runs = socket.assigns[:activity_runs] || []

    updated_runs =
      Enum.map(activity_runs, fn
        %{id: ^run_id} = run ->
          run
          |> Map.put(:status, :completed)
          |> Map.put(:completed_at, DateTime.utc_now())
          |> Map.merge(result_metadata)

        run ->
          run
      end)

    assign(socket, :activity_runs, updated_runs)
  end

  def fail_activity_run(socket, run_id, error) do
    activity_runs = socket.assigns[:activity_runs] || []

    updated_runs =
      Enum.map(activity_runs, fn
        %{id: ^run_id} = run ->
          run
          |> Map.put(:status, :failed)
          |> Map.put(:error, error)
          |> Map.put(:failed_at, DateTime.utc_now())

        run ->
          run
      end)

    assign(socket, :activity_runs, updated_runs)
  end

  # --- Session Memory & Digest ---

  def persist_session_memory(socket, _session_id, _memory_data) do
    # Foundry SpecKit integration
    # This would call SessionMemory.persist/2 in real implementation
    socket
  end

  def build_session_digest(socket, _options \\ []) do
    messages = socket.assigns[:messages] || []
    project_root = socket.assigns[:project_root] || ""

    digest = %{
      messages_count: length(messages),
      last_updated: DateTime.utc_now(),
      project_context: project_root,
      proposals: socket.assigns[:pending_proposals] || []
    }

    assign(socket, :session_digest, digest)
  end

  # --- Foundry System Prompt Building ---

  def build_run_system_prompt(socket, run_context \\ nil) do
    project_root = socket.assigns[:project_root] || ""

    base_prompt = """
    # Target Project Boundary

    The target platform for this chat is the reference iGaming project.
    Target project root: #{project_root}

    Treat this directory as the authoritative workspace for project discovery,
    code inspection, and Mix commands.

    ---
    """

    case run_context do
      nil ->
        base_prompt

      _context ->
        session_digest = socket.assigns[:session_digest] || %{}
        context_prompt = format_session_context(session_digest)
        base_prompt <> "\n" <> context_prompt
    end
  end

  # --- Foundry Retrieval Context ---

  def get_retrieval_context(socket, mode \\ :default) do
    project_root = socket.assigns[:project_root] || ""
    session_id = socket.assigns[:session_id]

    case mode do
      :full ->
        %{
          project_root: project_root,
          session_id: session_id,
          session_digest: socket.assigns[:session_digest],
          activity_runs: socket.assigns[:activity_runs]
        }

      _ ->
        %{
          project_root: project_root,
          session_id: session_id
        }
    end
  end

  def select_retrieval_mode(socket, mode) do
    assign(socket, :retrieval_mode, mode)
  end

  # --- Trace Events ---

  def append_trace_event(socket, run_id, event) do
    activity_runs = socket.assigns[:activity_runs] || []

    updated_runs =
      Enum.map(activity_runs, fn
        %{id: ^run_id} = run ->
          trace_events = run[:trace_events] || []
          Map.put(run, :trace_events, [event | trace_events])

        run ->
          run
      end)

    assign(socket, :activity_runs, updated_runs)
  end

  # --- UI Rendering Helpers ---

  def format_proposal_message(proposal) when is_map(proposal) do
    %{
      id: proposal["id"],
      title: proposal["title"] || "Untitled Change",
      description: proposal["description"],
      status: proposal["status"] || "pending"
    }
  end

  def format_activity_run(run) when is_map(run) do
    %{
      id: run[:id],
      status: run[:status],
      duration: calculate_duration(run),
      event_count: length(run[:trace_events] || [])
    }
  end

  # --- Private Helpers ---

  defp format_session_context(digest) do
    """
    ## Session Context

    Messages in session: #{digest[:messages_count] || 0}
    Last activity: #{format_timestamp(digest[:last_updated])}
    """
  end

  defp calculate_duration(run) do
    case {run[:created_at], run[:completed_at] || run[:failed_at]} do
      {start, finish} when not is_nil(start) and not is_nil(finish) ->
        DateTime.diff(finish, start, :millisecond)

      _ ->
        nil
    end
  end

  defp format_timestamp(nil), do: "never"

  defp format_timestamp(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
