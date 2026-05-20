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
  alias FoundryWeb.ChatConfig

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

  def finalize_session_digest(
        socket,
        request_ref,
        _response,
        artifact \\ nil,
        lock_session_label? \\ false
      ) do
    run = find_activity_run(socket.assigns.activity_runs, request_ref)

    socket.assigns.session_digest
    |> normalize_session_digest()
    |> maybe_lock_session_label(lock_session_label?)
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
    workspace_id = socket.assigns.workspace_id
    project_fingerprint = socket.assigns.project_fingerprint
    selected_model = socket.assigns.selected_model

    case save_session_state(
           session_id,
           messages,
           session_digest,
           workspace_id,
           project_fingerprint,
           selected_model
         ) do
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
    extracted = SessionMemory.extract_hidden(response)
    cleaned_response = extracted.response

    memory_result =
      persist_session_memory(project_root, socket.assigns.session_id, metadata, extracted.memory)

    session_title =
      extracted.session.payload
      |> normalize_session_title()

    if extracted.session.error do
      Logger.warning(
        "Failed to parse session title metadata: #{inspect(extracted.session.error)}"
      )
    end

    Map.merge(memory_result, %{response: cleaned_response, session_title: session_title})
  end

  def maybe_record_memory_trace(socket, _request_ref, %{artifact: nil, error: nil}), do: socket

  def maybe_record_memory_trace(socket, request_ref, %{artifact: artifact})
      when artifact != nil do
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
    loader = ChatConfig.hook(:load_session)

    result =
      case loader do
        fun when is_function(fun, 1) -> fun.(session_id)
        _ -> FileSessionStore.load(session_id)
      end

    case result do
      {:ok, session} when is_map(session) ->
        {:ok, session}

      {:ok, nil} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def save_session_state(
        session_id,
        messages,
        session_digest,
        workspace_id,
        project_fingerprint,
        selected_model
      ) do
    save_hook = ChatConfig.hook(:save_messages)

    if is_function(save_hook, 3) do
      case save_hook.(session_id, messages, session_digest) do
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      case load_session(session_id) do
        {:ok, existing} when is_map(existing) ->
          FileSessionStore.update(session_id, %{
            messages: messages,
            session_digest: session_digest,
            selected_model_id: selected_model && selected_model.id,
            selected_provider: selected_model && to_string(selected_model.provider),
            model: selected_model && selected_model.model_id,
            project_fingerprint: project_fingerprint,
            workspace_id: workspace_id
          })
          |> case do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end

        {:ok, nil} ->
          FileSessionStore.create(%{
            id: session_id,
            workspace_id: workspace_id,
            project_fingerprint: project_fingerprint,
            messages: messages,
            session_digest: session_digest,
            selected_model_id: selected_model && selected_model.id,
            selected_provider: selected_model && to_string(selected_model.provider),
            model: selected_model && selected_model.model_id
          })
          |> case do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def rename_session(session_id, title) when is_binary(title) do
    rename_hook = ChatConfig.hook(:rename_session)

    result =
      case rename_hook do
        fun when is_function(fun, 2) -> fun.(session_id, title)
        _ -> FileSessionStore.rename(session_id, title)
      end

    case result do
      {:ok, session} when is_map(session) -> {:ok, session}
      :ok -> load_session(session_id)
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Helpers ---

  defp persist_session_memory(_project_root, _session_id, _metadata, %{payload: nil, error: nil}) do
    %{artifact: nil, error: nil}
  end

  defp persist_session_memory(_project_root, _session_id, _metadata, %{payload: nil, error: error}) do
    Logger.warning("Failed to parse session memory payload: #{inspect(error)}")
    %{artifact: nil, error: error}
  end

  defp persist_session_memory(project_root, session_id, metadata, %{payload: memory_payload}) do
    persist_hook = ChatConfig.hook(:persist_session_memory)

    result =
      case persist_hook do
        fun when is_function(fun, 4) ->
          fun.(project_root, session_id, memory_payload, metadata || %{})

        _ ->
          SessionMemory.persist(project_root, session_id, memory_payload, metadata || %{})
      end

    case result do
      {:ok, artifact} ->
        %{artifact: artifact, error: nil}

      {:error, :empty_memory_payload} ->
        %{artifact: nil, error: nil}

      {:error, reason} ->
        Logger.warning("Failed to persist memory: #{inspect(reason)}")
        %{artifact: nil, error: reason}
    end
  end

  defp normalize_session_title(nil), do: nil

  defp normalize_session_title(%{"title" => title}) when is_binary(title) do
    normalized =
      title
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    cond do
      normalized == "" -> nil
      String.contains?(normalized, ["\n", "\r"]) -> nil
      String.length(normalized) > 40 -> nil
      true -> normalized
    end
  end

  defp normalize_session_title(_payload), do: nil

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
      nil ->
        digest

      formatted ->
        digest
        |> Map.put("recent_finding", formatted)
        |> Map.put(
          "recent_findings",
          ["#{formatted["title"]} (#{formatted["path"]})"]
        )
    end
  end

  defp format_recent_finding(%{title: title, path: path}),
    do: %{"title" => title, "path" => path}

  defp format_recent_finding(_artifact), do: nil

  defp maybe_put_proposal(digest, nil), do: digest

  defp maybe_put_proposal(digest, proposal) do
    Map.put(digest, "last_proposal", stringify_atom_keys(proposal))
  end

  defp maybe_lock_session_label(digest, true),
    do: Map.put_new(digest, "session_label_locked", true)

  defp maybe_lock_session_label(digest, _lock_session_label?), do: digest

  defp stringify_atom_keys(map) do
    Enum.reduce(map, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, Atom.to_string(k), v)
      {k, v}, acc -> Map.put(acc, k, v)
    end)
  end

  # --- Autoplan Review Pipeline (ADR-033) ---

  @doc """
  Runs the three-phase pre-plan review for :behavioral and :compliance changes.

  Returns %{decisions: [...], open_questions: [...], phase_log: [...]} where:
  - decisions: auto-resolved decisions with rationale
  - open_questions: D<N>-formatted questions for genuine ambiguities
  - phase_log: per-phase summary for the proposal review panel
  """
  def build_autoplan_review(change_class, autoplan_ctx, session_digest)
      when change_class in [:behavioral, :compliance] do
    phase_a = run_phase_a(autoplan_ctx, session_digest)
    phase_b = run_phase_b(change_class, autoplan_ctx, session_digest)
    phase_c = run_phase_c(autoplan_ctx, session_digest)

    all_decisions = phase_a.decisions ++ phase_b.decisions ++ phase_c.decisions
    open_questions = phase_a.open_questions ++ phase_b.open_questions ++ phase_c.open_questions

    %{
      decisions: all_decisions,
      open_questions: open_questions,
      phase_log: [
        %{phase: "A", label: "Business Fit", summary: phase_a.summary},
        %{phase: "B", label: "Governance", summary: phase_b.summary},
        %{phase: "C", label: "Architecture", summary: phase_c.summary}
      ]
    }
  end

  def build_autoplan_review(_change_class, _ctx, _digest), do: %{decisions: [], open_questions: [], phase_log: []}

  defp run_phase_a(ctx, _digest) do
    pattern_match = ctx[:pattern_match]
    spec_coverage = ctx[:spec_coverage]

    cond do
      pattern_match && spec_coverage ->
        %{
          decisions: [%{phase: "A", decision: "Reuse existing pattern: #{pattern_match}", auto: true}],
          open_questions: [],
          summary: "Pattern found and spec covers the case — no ambiguity."
        }

      pattern_match ->
        %{
          decisions: [%{phase: "A", decision: "Existing pattern found: #{pattern_match}", auto: true}],
          open_questions: [%{phase: "A", question: "Spec-kit is silent on scope for this pattern. Confirm intended behaviour."}],
          summary: "Pattern found but spec-kit silent on scope — surfacing scope question."
        }

      true ->
        %{
          decisions: [],
          open_questions: [%{phase: "A", question: "No existing pattern found. What is the narrowest version that proves this feature works?"}],
          summary: "No pattern found — scope ambiguity surfaced."
        }
    end
  end

  defp run_phase_b(change_class, ctx, digest) do
    sensitive_touched = ctx[:sensitive_resources_touched] || []
    class_ambiguous = ctx[:class_ambiguous] || false

    cond do
      change_class == :structural and sensitive_touched == [] ->
        %{
          decisions: [%{phase: "B", decision: "Class: :structural, no sensitive resources — approval by any developer", auto: true}],
          open_questions: [],
          summary: "Governance auto-resolved: structural change, no sensitive boundary."
        }

      class_ambiguous ->
        %{
          decisions: [],
          open_questions: [%{phase: "B", question: "Change class is ambiguous between :structural and :behavioral. Which class applies?"}],
          summary: "Class ambiguous — surfacing classification question."
        }

      sensitive_touched != [] ->
        approver = Map.get(digest || %{}, "sensitive_lead", "Sensitive lead")
        %{
          decisions: [%{phase: "B", decision: "Sensitive resources touched: #{Enum.join(sensitive_touched, ", ")} — requires #{approver} approval", auto: true}],
          open_questions: [],
          summary: "Sensitive resources identified, approval chain set."
        }

      true ->
        %{
          decisions: [%{phase: "B", decision: "Change class: #{change_class} — approval chain follows standard governance", auto: true}],
          open_questions: [],
          summary: "Governance resolved via standard #{change_class} path."
        }
    end
  end

  defp run_phase_c(ctx, _digest) do
    resources = ctx[:resources_touched] || []
    needs_migration = ctx[:migration_needed] || false
    side_effect_count = ctx[:side_effect_count] || 0
    reactor_boundary_unclear = ctx[:reactor_boundary_unclear] || false

    cond do
      reactor_boundary_unclear ->
        %{
          decisions: [],
          open_questions: [%{phase: "C", question: "Multiple side effects detected but Reactor boundary is unclear. Model as Reactor (per INV-019)?"}],
          summary: "Reactor boundary ambiguous — surfacing architecture question."
        }

      side_effect_count > 1 ->
        %{
          decisions: [%{phase: "C", decision: "#{side_effect_count} side effects — must model as Reactor per INV-019", auto: true}],
          open_questions: [],
          summary: "Multiple side effects auto-resolved to Reactor pattern."
        }

      length(resources) == 1 and not needs_migration and side_effect_count <= 1 ->
        %{
          decisions: [%{phase: "C", decision: "Single resource (#{hd(resources)}), no migration, single side effect — resource action pattern", auto: true}],
          open_questions: [],
          summary: "Architecture auto-resolved: single resource action."
        }

      true ->
        %{
          decisions: [%{phase: "C", decision: "Resources: #{Enum.join(resources, ", ")}, migration: #{needs_migration}", auto: true}],
          open_questions: [],
          summary: "Architecture signals gathered."
        }
    end
  end
end
