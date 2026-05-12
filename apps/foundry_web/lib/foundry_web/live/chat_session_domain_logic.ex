defmodule FoundryWeb.ChatSessionDomainLogic do
  @moduledoc """
  Foundry-specific domain logic for chat sessions.

  This module encapsulates all Foundry-specific concerns extracted from ChatSession:
  - Proposal management (apply, revise, cancel)
  - Activity run tracking with ChatTrace integration
  - Session memory and digest building
  - Run context preparation (retrieval, proposals, system prompts)
  - Message formatting and metadata attachment
  - Session persistence via FileSessionStore

  ChatSession acts as the orchestration layer calling these functions,
  keeping the live view code focused on event routing and state management.
  """

  import Phoenix.Component, only: [update: 3]
  require Ash.Query
  require Logger

  alias Foundry.Chat.FileSessionStore
  alias Foundry.Chat.MessageClassifier
  alias Foundry.Chat.Retrieval, as: ChatRetrieval
  alias Foundry.ChatTrace
  alias Foundry.SpecKit.SessionMemory

  # --- Proposal Management ---

  def handle_proposal_apply(socket, proposal_id) do
    socket
    |> update(:messages, &update_latest_proposal_message(&1, proposal_id, :applied))
    |> update(:session_digest, fn digest ->
      digest
      |> normalize_session_digest()
      |> Map.put("active_proposal_id", nil)
      |> Map.put("active_proposal_status", "applied")
    end)
    |> Phoenix.LiveView.push_event("graph:proposal_overlay", %{clear: true})
    |> Phoenix.LiveView.push_event(
      "graph:delta",
      active_proposal_delta(socket.assigns.messages, proposal_id)
    )
    |> persist_updated_chat()
  end

  def handle_proposal_revise(socket, proposal_id) do
    socket
    |> update(:messages, &update_latest_proposal_message(&1, proposal_id, :awaiting_revision))
    |> update(:session_digest, fn digest ->
      digest
      |> normalize_session_digest()
      |> Map.put("active_proposal_id", proposal_id)
      |> Map.put("active_proposal_status", "awaiting_revision")
      |> Map.put("revision_of_proposal_id", proposal_id)
    end)
    |> Phoenix.LiveView.push_event(
      "graph:proposal_overlay",
      active_proposal_overlay(socket.assigns.messages, proposal_id)
    )
    |> persist_updated_chat()
  end

  def handle_proposal_cancel(socket, proposal_id) do
    socket
    |> update(:messages, &update_latest_proposal_message(&1, proposal_id, :cancelled))
    |> update(:session_digest, fn digest ->
      digest
      |> normalize_session_digest()
      |> Map.put("active_proposal_id", nil)
      |> Map.put("active_proposal_status", "cancelled")
      |> Map.put("revision_of_proposal_id", nil)
    end)
    |> Phoenix.LiveView.push_event("graph:proposal_overlay", %{clear: true})
    |> persist_updated_chat()
  end

  def get_proposal_file_preview(socket, proposal_id, path) do
    proposal_file_preview_payload(socket.assigns.messages, proposal_id, path)
  end

  # --- Activity Run Management ---

  def create_activity_run(message, request_ref, run_context, llm_provider_fn, llm_diagnostics_fn) do
    %{
      id: System.unique_integer([:positive, :monotonic]),
      request_ref: request_ref,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      finished_at: nil,
      status: :running,
      provider: llm_provider_fn.(),
      diagnostics: llm_diagnostics_fn.(run_context.diagnostics),
      mode: run_context.mode,
      proposal: run_context.proposal,
      user_message: message,
      response_preview: nil,
      events: [],
      grouped_events: [],
      phase_groups: [],
      phase_counts: %{},
      provenance: %{},
      event_count: 0,
      grouped_event_count: 0,
      tool_count: 0,
      file_count: 0,
      tools: [],
      files: [],
      read_files: [],
      written_files: [],
      token_usage: %{},
      total_tokens: nil,
      metadata: %{},
      error: nil
    }
  end

  def update_activity_run(socket, request_ref, fun) do
    update(socket, :activity_runs, fn runs ->
      Enum.map(runs, fn
        %{request_ref: ^request_ref} = run -> fun.(run)
        run -> run
      end)
    end)
  end

  def append_trace_event_to_run(run, trace_event) do
    normalized = ChatTrace.normalize(trace_event["provider"] || "unknown", trace_event)
    events = [normalized | run.events] |> Enum.take(250)
    summary = ChatTrace.summarize_run(events)

    run
    |> Map.put(:events, events)
    |> Map.merge(summary)
  end

  def complete_activity_run(socket, request_ref, response, metadata) do
    update_activity_run(socket, request_ref, fn run ->
      usage = normalize_usage(metadata)

      run
      |> Map.put(:status, :completed)
      |> Map.put(:finished_at, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put(:response_preview, summarize_response(response))
      |> Map.put(:metadata, metadata || %{})
      |> Map.put(:token_usage, usage)
      |> Map.put(:total_tokens, usage_total(usage))
    end)
  end

  def fail_activity_run(socket, request_ref, reason, format_error_fn) do
    update_activity_run(socket, request_ref, fn run ->
      run
      |> Map.put(:status, :error)
      |> Map.put(:finished_at, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put(:error, format_error_fn.(reason))
    end)
  end

  def find_activity_run(activity_runs, request_ref) do
    Enum.find(activity_runs, fn run -> run.request_ref == request_ref end)
  end

  # --- Run Context Building ---

  def build_run_context(
        socket,
        message,
        hook_fn,
        normalize_digest_fn,
        build_prompt_fn,
        project_root
      ) do
    case hook_fn.(:build_run_context) do
      nil ->
        mode = MessageClassifier.classify_mode(message)

        case ChatRetrieval.prepare(project_root, message, socket.assigns.session_digest || %{}) do
          {:ok, retrieval} ->
            Logger.debug("ChatRetrieval.prepare succeeded for project_root: #{project_root}")
            proposal =
              if mode == :change do
                case ChatRetrieval.create_proposal(
                       message,
                       "studio@local",
                       retrieval.tool_results,
                       socket.assigns.session_digest || %{},
                       project_root
                     ) do
                  {:ok, proposal} -> proposal
                  {:error, _reason} -> nil
                end
              end

            session_digest =
              socket.assigns.session_digest
              |> normalize_digest_fn.()
              |> prepare_session_digest(retrieval, mode, proposal)

            system_prompt =
              build_prompt_fn.(project_root, retrieval, session_digest, mode, proposal)

            proposal_trace =
              if proposal do
                [
                  %{
                    "provider" => "foundry",
                    "type" => "foundry.proposal.created",
                    "phase" => "proposal",
                    "message" => "Created proposal draft #{proposal.id}",
                    "proposal" => proposal
                  }
                ]
              else
                []
              end

            {:ok,
             %{
               mode: mode,
               retrieval: retrieval,
               proposal: proposal,
               session_digest: session_digest,
               system_prompt: system_prompt,
               trace_events: retrieval.trace_events ++ proposal_trace,
               diagnostics: %{
                 mode: Atom.to_string(mode),
                 context_cache: Atom.to_string(retrieval.cached_context.cache),
                 context_fingerprint: retrieval.cached_context.fingerprint,
                 proposal_id: proposal && proposal.id
               }
             }}

          {:error, reason} ->
            Logger.error("ChatRetrieval.prepare failed: #{inspect(reason)}")
            {:error, reason}
        end

      fun ->
        fun.(socket, message)
    end
  end

  # --- Session Memory & Digest ---

  def finalize_session_digest(socket, request_ref, _response, artifact \\ nil) do
    run = find_activity_run(socket.assigns.activity_runs, request_ref)

    socket.assigns.session_digest
    |> normalize_session_digest()
    |> prepend_recent_finding(artifact)
    |> maybe_put_proposal(run && run.proposal)
  end

  def prepare_session_digest(digest, retrieval, mode, proposal) do
    digest
    |> Map.put("retrieval_mode", Atom.to_string(mode))
    |> Map.put("cached_context_fingerprint", retrieval.cached_context.fingerprint)
    |> Map.put("proposal_draft", proposal && stringify_atom_keys(proposal))
  end

  def normalize_session_digest(nil), do: %{}
  def normalize_session_digest(digest) when is_map(digest), do: digest
  def normalize_session_digest(_digest), do: %{}

  # --- Persist & Message Updates ---

  def persist_updated_chat(socket) do
    session_id = socket.assigns.session_id
    messages = socket.assigns.messages
    session_digest = socket.assigns.session_digest

    case save_session_state(session_id, messages, session_digest) do
      :ok ->
        socket

      {:error, reason} ->
        Logger.error("Failed to persist chat: #{inspect(reason)}")
        socket
    end
  end

  def persist_turn_memory(socket, request_ref, response) do
    project_root = socket.assigns.project_root
    run = find_activity_run(socket.assigns.activity_runs, request_ref)

    metadata = run && run.metadata

    case SessionMemory.persist(
           project_root,
           socket.assigns.session_id,
           %{
             messages: socket.assigns.messages,
             response: response
           },
           metadata
         ) do
      {:ok, payload} ->
        %{response: response, artifact: payload[:artifact], error: nil}

      {:error, reason} ->
        Logger.warning("Failed to persist memory: #{inspect(reason)}")
        %{response: response, artifact: nil, error: reason}
    end
  end

  def maybe_record_memory_trace(socket, _request_ref, %{artifact: nil, error: nil}), do: socket

  def maybe_record_memory_trace(socket, request_ref, %{artifact: artifact}) when artifact != nil do
    update_activity_run(socket, request_ref, fn run ->
      trace_event = %{
        "type" => "foundry.memory.recorded",
        "phase" => "memory",
        "message" => "Recorded turn in session memory"
      }

      append_trace_event_to_run(run, trace_event)
    end)
  end

  def maybe_record_memory_trace(socket, request_ref, %{error: error}) when error != nil do
    update_activity_run(socket, request_ref, fn run ->
      trace_event = %{
        "type" => "foundry.memory.failed",
        "phase" => "memory",
        "message" => "Failed to record session memory: #{inspect(error)}"
      }

      append_trace_event_to_run(run, trace_event)
    end)
  end

  def maybe_attach_message_metadata(message, nil), do: message

  def maybe_attach_message_metadata(message, run) do
    message
    |> maybe_put_partial(run)
    |> maybe_put_message_proposal(run.proposal)
  end

  def maybe_put_partial(message, %{metadata: metadata}) when is_map(metadata) do
    case metadata["partial"] do
      true -> Map.put(message, "partial", true)
      _ -> message
    end
  end

  def maybe_put_partial(message, _run), do: message

  def maybe_put_message_proposal(message, nil), do: message
  def maybe_put_message_proposal(message, proposal), do: Map.put(message, "proposal", proposal)

  # --- Message Helpers ---

  def update_latest_proposal_message(messages, proposal_id, status) do
    index = latest_proposal_message_index(messages, proposal_id)

    case index do
      nil ->
        messages

      idx ->
        List.update_at(messages, idx, fn msg ->
          proposal = msg["proposal"] || %{}
          updated_proposal = Map.put(proposal, "status", Atom.to_string(status))
          Map.put(msg, "proposal", updated_proposal)
        end)
    end
  end

  def latest_proposal_message_index(messages, proposal_id) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {%{"proposal" => %{"id" => id}}, idx} when id == proposal_id -> idx
      _ -> nil
    end)
  end

  def active_proposal_overlay(messages, proposal_id) do
    proposal = find_proposal(messages, proposal_id)

    if proposal do
      %{
        proposal_id: proposal_id,
        proposal: stringify_atom_keys(proposal),
        created_at: proposal[:created_at]
      }
    else
      %{proposal_id: proposal_id}
    end
  end

  def active_proposal_delta(messages, proposal_id) do
    proposal = find_proposal(messages, proposal_id)

    %{
      proposal_id: proposal_id,
      graph_update: proposal && Map.get(proposal, :graph_update, %{})
    }
  end

  def proposal_file_preview_payload(messages, proposal_id, path) do
    proposal = find_proposal(messages, proposal_id)

    case proposal do
      nil ->
        nil

      _ ->
        files = proposal[:created_files] || proposal[:modified_files] || []
        file = Enum.find(files, &(Map.get(&1, :path) == path))

        if file do
          %{
            proposal_id: proposal_id,
            path: path,
            preview: Map.get(file, :preview),
            language: Map.get(file, :language)
          }
        else
          nil
        end
    end
  end

  def find_proposal(messages, proposal_id) do
    Enum.find_value(messages, fn msg ->
      proposal = msg["proposal"]
      if proposal && proposal["id"] == proposal_id, do: proposal
    end)
  end

  # --- Session Persistence ---

  def load_session(session_id) do
    case FileSessionStore.load(session_id) do
      {:ok, session} when is_map(session) ->
        {:ok, session}

      {:ok, nil} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def save_session_state(session_id, messages, session_digest) do
    case load_session(session_id) do
      {:ok, existing} when is_map(existing) ->
        FileSessionStore.update(session_id, %{messages: messages, session_digest: session_digest})
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, nil} ->
        FileSessionStore.create(%{
          id: session_id,
          messages: messages,
          session_digest: session_digest
        })
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Helpers ---

  defp summarize_response(response) when is_binary(response) do
    response
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 180)
  end

  defp normalize_usage(metadata) when is_map(metadata) do
    case metadata[:usage] || metadata["usage"] do
      usage when is_map(usage) -> usage
      _ -> %{}
    end
  end

  defp normalize_usage(_metadata), do: %{}

  defp usage_total(%{total_tokens: total}) when is_integer(total), do: total

  defp usage_total(usage) when is_map(usage) do
    (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0) || nil
  end

  defp usage_total(_usage), do: nil

  defp prepend_recent_finding(digest, nil), do: digest

  defp prepend_recent_finding(digest, artifact) do
    case format_recent_finding(artifact) do
      nil -> digest
      formatted -> Map.put(digest, "recent_finding", formatted)
    end
  end

  defp format_recent_finding(%{title: title, path: path}),
    do: %{title: title, path: path}

  defp format_recent_finding(_artifact), do: nil

  defp maybe_put_proposal(digest, nil), do: digest

  defp maybe_put_proposal(digest, proposal) do
    Map.put(digest, "last_proposal", stringify_atom_keys(proposal))
  end

  defp stringify_atom_keys(map) do
    Enum.reduce(map, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, Atom.to_string(k), v)
      {k, v}, acc -> Map.put(acc, k, v)
    end)
  end
end
