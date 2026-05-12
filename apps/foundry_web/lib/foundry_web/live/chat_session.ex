defmodule FoundryWeb.ChatSession do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  require Ash.Query

  alias Foundry.Chat.FileSessionStore
  alias Foundry.Chat.Retrieval, as: ChatRetrieval
  alias Foundry.Chat.Session, as: ChatRecord
  alias Foundry.ChatTrace
  alias Foundry.SpecKit.SessionMemory

  def mount(socket, session) do
    session_id = Map.get(session, "chat_session_id", Ecto.UUID.generate())

    {messages, session_digest, load_error} =
      case load_session(session_id) do
        {:ok, %ChatRecord{} = chat_session} ->
          {chat_session.messages, chat_session.session_digest || %{}, nil}

        {:ok, nil} ->
          {[], %{}, nil}

        {:error, reason} ->
          {[], %{}, persistence_error("Failed to load chat session", reason)}
      end

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:messages, messages)
      |> assign(:session_digest, session_digest)
      |> assign(:input, "")
      |> assign(:loading, false)
      |> assign(:error, load_error)
      |> assign(:active_request_ref, nil)
      |> assign(:active_request_task, nil)
      |> assign(:project_root, project_root())
      |> assign(:show_system_context, false)
      |> assign(:system_context_prompt, nil)
      |> assign(:system_context_error, nil)
      |> assign(:llm_provider, llm_provider())
      |> assign(:llm_diagnostics, llm_diagnostics())
      |> assign(:chat_view, :conversation)
      |> assign(:activity_runs, [])
      |> assign(:selected_activity_run_id, nil)
      |> assign(:workspace_id, Map.get(session, "foundry_workspace_id", Ecto.UUID.generate()))
      |> assign(:open_session_ids, [])
      |> assign(:active_session_id, nil)
      |> assign(:sessions_by_id, %{})
      |> assign(:last_session_summary_at, nil)

    {:ok, socket}
  end

  # --- Workspace / session tab events ---

  def handle_event(
        "chat_workspace_hydrate",
        %{"open_session_ids" => open_ids, "active_session_id" => active_id},
        socket
      ) do
    open_ids = Enum.filter(open_ids, &is_binary/1)
    project_fp = project_fingerprint()

    sessions_by_id =
      Enum.reduce(open_ids, %{}, fn id, acc ->
        case FileSessionStore.load(id) do
          {:ok, session} when is_map(session) -> Map.put(acc, id, session)
          _ -> acc
        end
      end)

    valid_open_ids = Enum.filter(open_ids, &Map.has_key?(sessions_by_id, &1))

    active_id =
      cond do
        active_id in valid_open_ids -> active_id
        valid_open_ids != [] -> List.first(valid_open_ids)
        true -> nil
      end

    socket =
      socket
      |> assign(:open_session_ids, valid_open_ids)
      |> assign(:active_session_id, active_id)
      |> assign(:sessions_by_id, sessions_by_id)
      |> maybe_load_active_session_into_chat(active_id)
      |> push_workspace_state()

    _ = project_fp
    {:noreply, socket}
  end

  def handle_event("chat_workspace_hydrate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("chat_session_new", _params, socket) do
    session_id = Ecto.UUID.generate()
    project_fp = project_fingerprint()

    case FileSessionStore.create(%{
           id: session_id,
           workspace_id: socket.assigns.workspace_id,
           project_fingerprint: project_fp,
           title: "New session"
         }) do
      {:ok, session} ->
        open_ids = [session_id | socket.assigns.open_session_ids]
        sessions_by_id = Map.put(socket.assigns.sessions_by_id, session_id, session)

        socket =
          socket
          |> assign(:open_session_ids, open_ids)
          |> assign(:active_session_id, session_id)
          |> assign(:sessions_by_id, sessions_by_id)
          |> switch_to_session(session_id)
          |> push_event("chat:scroll_to_bottom", %{force: true})
          |> push_workspace_state()

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("chat_session_open", %{"id" => id}, socket) do
    sessions_by_id = socket.assigns.sessions_by_id

    sessions_by_id =
      if Map.has_key?(sessions_by_id, id) do
        sessions_by_id
      else
        case FileSessionStore.load(id) do
          {:ok, session} when is_map(session) -> Map.put(sessions_by_id, id, session)
          _ -> sessions_by_id
        end
      end

    if Map.has_key?(sessions_by_id, id) do
      open_ids =
        if id in socket.assigns.open_session_ids do
          socket.assigns.open_session_ids
        else
          [id | socket.assigns.open_session_ids]
        end

      socket =
        socket
        |> assign(:open_session_ids, open_ids)
        |> assign(:active_session_id, id)
        |> assign(:sessions_by_id, sessions_by_id)
        |> maybe_load_active_session_into_chat(id)
        |> push_event("chat:scroll_to_bottom", %{force: true})
        |> push_workspace_state()

      {:noreply, socket}
    else
      {:noreply, assign(socket, :sessions_by_id, sessions_by_id)}
    end
  end

  def handle_event("chat_session_switch", %{"id" => id}, socket) do
    if id in socket.assigns.open_session_ids do
      socket =
        socket
        |> assign(:active_session_id, id)
        |> maybe_load_active_session_into_chat(id)
        |> push_event("chat:scroll_to_bottom", %{force: true})
        |> push_workspace_state()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("chat_session_close", %{"id" => id}, socket) do
    open_ids = List.delete(socket.assigns.open_session_ids, id)

    active_id =
      cond do
        socket.assigns.active_session_id != id -> socket.assigns.active_session_id
        open_ids == [] -> nil
        true -> List.first(open_ids)
      end

    socket =
      socket
      |> assign(:open_session_ids, open_ids)
      |> assign(:active_session_id, active_id)
      |> maybe_load_active_session_into_chat(active_id)
      |> push_event("chat:scroll_to_bottom", %{force: true})
      |> push_workspace_state()

    {:noreply, socket}
  end

  def handle_event("chat_session_rename", %{"id" => id, "title" => title}, socket) do
    case FileSessionStore.rename(id, title) do
      {:ok, updated_session} ->
        sessions_by_id = Map.put(socket.assigns.sessions_by_id, id, updated_session)
        {:noreply, assign(socket, :sessions_by_id, sessions_by_id)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("chat_session_delete", %{"id" => id}, socket) do
    FileSessionStore.delete(id)
    open_ids = List.delete(socket.assigns.open_session_ids, id)
    sessions_by_id = Map.delete(socket.assigns.sessions_by_id, id)

    active_id =
      cond do
        socket.assigns.active_session_id != id -> socket.assigns.active_session_id
        open_ids == [] -> nil
        true -> List.first(open_ids)
      end

    socket =
      socket
      |> assign(:open_session_ids, open_ids)
      |> assign(:active_session_id, active_id)
      |> assign(:sessions_by_id, sessions_by_id)
      |> maybe_load_active_session_into_chat(active_id)
      |> push_event("chat:scroll_to_bottom", %{force: true})
      |> push_workspace_state()

    {:noreply, socket}
  end

  def handle_event("toggle_system_context", _params, socket) do
    if socket.assigns.show_system_context do
      {:noreply, assign(socket, :show_system_context, false)}
    else
      {:noreply, load_system_context(socket)}
    end
  end

  def handle_event("update_chat_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input, message)}
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      with {:ok, run_context} <- build_run_context(socket, message) do
        user_msg = %{
          "role" => "user",
          "content" => message,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        request_ref = make_ref()
        activity_run = new_activity_run(message, request_ref, run_context)
        persisted_messages = socket.assigns.messages ++ [user_msg]

        assistant_msg = %{
          "role" => "assistant",
          "content" => "",
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        messages = persisted_messages ++ [assistant_msg]

        case save_session_state(
               socket.assigns.session_id,
               persisted_messages,
               run_context.session_digest
             ) do
          :ok ->
            task = start_llm_stream(request_ref, persisted_messages, self(), run_context)

            socket =
              socket
              |> cancel_active_task()
              |> assign(:messages, messages)
              |> assign(:session_digest, run_context.session_digest)
              |> assign(:input, "")
              |> assign(:loading, true)
              |> assign(:error, nil)
              |> assign(:active_request_ref, request_ref)
              |> assign(:active_request_task, task)
              |> assign(:llm_diagnostics, llm_diagnostics(run_context.diagnostics))
              |> assign(
                :activity_runs,
                [activity_run | socket.assigns.activity_runs] |> Enum.take(12)
              )
              |> assign(:selected_activity_run_id, activity_run.id)
              |> push_event("chat:scroll_to_bottom", %{force: true})

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:error, persistence_error("Failed to save chat session", reason))
             |> assign(:loading, false)}
        end
      else
        {:error, reason} ->
          {:noreply, assign(socket, :error, format_request_error(reason))}
      end
    end
  end

  def handle_event("set_chat_view", %{"view" => view}, socket) do
    next_view = parse_chat_view(view)

    if next_view == :conversation do
      {:noreply,
       socket
       |> assign(:chat_view, next_view)
       |> push_event("chat:scroll_to_bottom", %{force: true})}
    else
      {:noreply, assign(socket, :chat_view, next_view)}
    end
  end

  def handle_event("summarize_session", _params, socket) do
    digest =
      socket.assigns.session_digest
      |> normalize_session_digest()
      |> build_session_summary(socket.assigns.messages, socket.assigns.activity_runs)

    socket =
      socket
      |> assign(:session_digest, digest)
      |> assign(:last_session_summary_at, Map.get(digest, "summary_updated_at"))
      |> persist_updated_chat()

    {:noreply, socket}
  end

  def handle_event("proposal_apply", %{"id" => proposal_id}, socket) do
    socket =
      socket
      |> update(:messages, &update_latest_proposal_message(&1, proposal_id, :applied))
      |> update(:session_digest, fn digest ->
        digest
        |> normalize_session_digest()
        |> Map.put("active_proposal_id", nil)
        |> Map.put("active_proposal_status", "applied")
      end)
      |> push_event("graph:proposal_overlay", %{clear: true})
      |> push_event("graph:delta", active_proposal_delta(socket.assigns.messages, proposal_id))
      |> persist_updated_chat()

    {:noreply, socket}
  end

  def handle_event("proposal_revise", %{"id" => proposal_id}, socket) do
    socket =
      socket
      |> update(:messages, &update_latest_proposal_message(&1, proposal_id, :awaiting_revision))
      |> update(:session_digest, fn digest ->
        digest
        |> normalize_session_digest()
        |> Map.put("active_proposal_id", proposal_id)
        |> Map.put("active_proposal_status", "awaiting_revision")
        |> Map.put("revision_of_proposal_id", proposal_id)
      end)
      |> push_event(
        "graph:proposal_overlay",
        active_proposal_overlay(socket.assigns.messages, proposal_id)
      )
      |> persist_updated_chat()

    {:noreply, socket}
  end

  def handle_event("proposal_cancel", %{"id" => proposal_id}, socket) do
    socket =
      socket
      |> update(:messages, &update_latest_proposal_message(&1, proposal_id, :cancelled))
      |> update(:session_digest, fn digest ->
        digest
        |> normalize_session_digest()
        |> Map.put("active_proposal_id", nil)
        |> Map.put("active_proposal_status", "cancelled")
        |> Map.put("revision_of_proposal_id", nil)
      end)
      |> push_event("graph:proposal_overlay", %{clear: true})
      |> persist_updated_chat()

    {:noreply, socket}
  end

  def handle_event(
        "open_proposal_file_preview",
        %{"proposal_id" => proposal_id, "path" => path},
        socket
      ) do
    socket =
      case proposal_file_preview_payload(socket.assigns.messages, proposal_id, path) do
        nil ->
          push_event(socket, "file_error", %{path: path, reason: "proposal_preview_missing"})

        payload ->
          push_event(socket, "proposal_file_preview", payload)
      end

    {:noreply, socket}
  end

  def handle_event("select_activity_run", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_activity_run_id, String.to_integer(id))}
  rescue
    _ -> {:noreply, socket}
  end

  def handle_event(_event, _params, _socket), do: :unhandled

  def handle_info({:llm_stream_delta, request_ref, delta}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      {:noreply, update(socket, :messages, &append_to_streaming_response(&1, delta))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_done, request_ref, response, metadata}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      memory_result = persist_turn_memory(socket, request_ref, response)

      socket =
        socket
        |> complete_activity_run(request_ref, memory_result.response, metadata)
        |> maybe_record_memory_trace(request_ref, memory_result)

      run = find_activity_run(socket.assigns.activity_runs, request_ref)
      messages = finalize_streaming_response(socket.assigns.messages, memory_result.response, run)

      digest =
        finalized_session_digest(
          socket,
          request_ref,
          memory_result.response,
          memory_result.artifact
        )

      {:noreply,
       finish_stream(
         assign(socket, :session_digest, digest),
         messages,
         save_session_state(socket.assigns.session_id, messages, digest)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_trace, request_ref, raw_event}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      trace_event = ChatTrace.normalize(llm_provider(), raw_event)

      {:noreply,
       update_activity_run(socket, request_ref, fn run -> append_trace_event(run, trace_event) end)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_error, request_ref, reason}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      messages = drop_empty_streaming_response(socket.assigns.messages)
      socket = fail_activity_run(socket, request_ref, reason)
      digest = finalized_session_digest(socket, request_ref, nil)

      {:noreply,
       finish_stream(
         assign(socket, :session_digest, digest),
         messages,
         save_session_state(socket.assigns.session_id, messages, digest),
         format_request_error(reason)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({ref, _result}, socket) when is_reference(ref) do
    if active_task_ref(socket) == ref do
      {:noreply, clear_active_task(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) do
    if active_task_ref(socket) == ref do
      case reason do
        :normal ->
          {:noreply, clear_active_task(socket)}

        :shutdown ->
          {:noreply, clear_active_task(socket)}

        {:shutdown, _} ->
          {:noreply, clear_active_task(socket)}

        _ ->
          messages = drop_empty_streaming_response(socket.assigns.messages)
          digest = finalized_session_digest(socket, socket.assigns.active_request_ref, nil)

          {:noreply,
           finish_stream(
             assign(socket, :session_digest, digest),
             messages,
             save_session_state(socket.assigns.session_id, messages, digest),
             format_task_shutdown_error(reason)
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, _socket), do: :unhandled

  def terminate(socket) do
    _socket = cancel_active_task(socket)
    :ok
  end

  defp build_run_context(socket, message) do
    case hook(:build_run_context) do
      nil ->
        project_root = socket.assigns.project_root
        mode = classify_mode(message)

        with {:ok, retrieval} <-
               ChatRetrieval.prepare(project_root, message, socket.assigns.session_digest || %{}) do
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
            |> normalize_session_digest()
            |> prepare_session_digest(retrieval, mode, proposal)

          system_prompt =
            build_run_system_prompt(project_root, retrieval, session_digest, mode, proposal)

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
        end

      fun ->
        fun.(socket, message)
    end
  end

  defp start_llm_stream(request_ref, messages, live_view_pid, run_context) do
    Task.Supervisor.async_nolink(FoundryWeb.ChatTaskSupervisor, fn ->
      Enum.each(run_context.trace_events, fn event ->
        send(live_view_pid, {:llm_stream_trace, request_ref, event})
      end)

      case call_llm_stream(
             messages,
             fn event ->
               send(live_view_pid, format_stream_event(request_ref, event))
             end,
             run_context
           ) do
        {:ok, response} when is_binary(response) ->
          send(live_view_pid, {:llm_stream_done, request_ref, response, %{}})

        {:ok, response, metadata} ->
          send(live_view_pid, {:llm_stream_done, request_ref, response, metadata || %{}})

        {:error, reason} ->
          send(live_view_pid, {:llm_stream_error, request_ref, reason})
      end
    end)
  end

  defp format_stream_event(request_ref, {:delta, text}),
    do: {:llm_stream_delta, request_ref, text}

  defp format_stream_event(request_ref, {:trace, event}),
    do: {:llm_stream_trace, request_ref, event}

  defp append_to_streaming_response(messages, delta) do
    update_last_message(messages, fn msg ->
      Map.update(msg, "content", delta, &(&1 <> delta))
    end)
  end

  defp finalize_streaming_response(messages, "", _run), do: messages

  defp finalize_streaming_response(messages, response, run) do
    update_last_message(messages, fn message ->
      message
      |> Map.put("content", response)
      |> maybe_attach_message_metadata(run)
    end)
  end

  defp drop_empty_streaming_response(messages) do
    case Enum.reverse(messages) do
      [%{"role" => "assistant", "content" => ""} | rest] -> Enum.reverse(rest)
      _ -> messages
    end
  end

  defp update_last_message(messages, fun) do
    case Enum.reverse(messages) do
      [last | rest] -> Enum.reverse([fun.(last) | rest])
      [] -> []
    end
  end

  defp load_session(session_id) do
    case hook(:load_session) do
      nil ->
        ChatRecord
        |> Ash.Query.filter(session_id: session_id)
        |> Ash.read_one(domain: Foundry.Chat)

      fun ->
        fun.(session_id)
    end
  end

  defp save_session_state(session_id, messages, session_digest) do
    FileSessionStore.update(session_id, %{
      "messages" => messages,
      "session_digest" => session_digest
    })

    case load_session(session_id) do
      {:ok, nil} ->
        case create_session(session_id, messages, session_digest) do
          {:ok, _session} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, %ChatRecord{} = existing} ->
        case update_session(existing, messages, session_digest) do
          {:ok, _session} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_session(session_id, messages, session_digest) do
    case hook(:save_messages) do
      nil ->
        ChatRecord
        |> Ash.Changeset.for_create(
          :create,
          %{session_id: session_id, messages: messages, session_digest: session_digest},
          domain: Foundry.Chat
        )
        |> Ash.create()

      fun ->
        invoke_save_hook(fun, session_id, messages, session_digest)
    end
  end

  defp update_session(existing, messages, session_digest) do
    case hook(:save_messages) do
      nil ->
        existing
        |> Ash.Changeset.for_update(
          :persist_messages,
          %{messages: messages, session_digest: session_digest},
          domain: Foundry.Chat
        )
        |> Ash.update()

      fun ->
        invoke_save_hook(fun, existing.session_id, messages, session_digest)
    end
  end

  defp invoke_save_hook(fun, session_id, messages, session_digest) do
    case :erlang.fun_info(fun, :arity) do
      {:arity, 3} -> fun.(session_id, messages, session_digest)
      _ -> fun.(session_id, messages)
    end
  end

  defp call_llm(messages) do
    case llm_provider() do
      :claude_code ->
        call_claude_code(messages, %{})

      :lm_studio ->
        call_lm_studio(messages, %{})

      :codex ->
        call_codex(messages, %{})

      :req_llm ->
        call_req_llm(messages)

      provider ->
        {:error, {:unknown_provider, provider}}
    end
  end

  defp call_llm_stream(messages, on_event, run_context) do
    case hook(:call_llm_stream) do
      nil ->
        case llm_provider() do
          :claude_code ->
            call_claude_code_stream(messages, on_event, run_context)

          :lm_studio ->
            call_lm_studio_stream(messages, on_event, run_context)

          :codex ->
            call_codex_stream(messages, on_event, run_context)

          _ ->
            call_llm(messages)
        end

      fun ->
        case :erlang.fun_info(fun, :arity) do
          {:arity, 3} -> fun.(messages, on_event, run_context)
          _ -> fun.(messages, on_event)
        end
    end
  end

  defp call_claude_code(messages, run_context) do
    call_claude_code_stream(messages, fn _event -> :ok end, run_context)
  end

  defp call_claude_code_stream(messages, on_event, run_context) do
    project_root = project_root()

    with {:ok, system_prompt} <- build_system_prompt(project_root, run_context) do
      opts = [
        system_prompt: system_prompt,
        timeout_ms: Application.get_env(:foundry, :claude_code, [])[:timeout_ms] || 120_000,
        model: Application.get_env(:foundry, :claude_code, [])[:model],
        project_root: project_root
      ]

      case Foundry.ClaudeCodeProvider.stream(messages, opts, fn
             {:delta, text} -> on_event.({:delta, text})
             _event -> :ok
           end) do
        {:ok, text, metadata} ->
          {:ok, text, metadata}

        {:error, :not_installed} ->
          {:ok, claude_not_installed_message()}

        {:error, {:timeout, partial_text, metadata}} ->
          if String.length(partial_text) > 0 do
            {:ok, partial_text, Map.put(metadata || %{}, :partial, true)}
          else
            {:error, :timeout}
          end

        {:error, {:exit_code, code, output}} ->
          {:error, {:claude_exit, code, String.slice(output, 0, 500)}}

        {:error, {:parse_error, reason, _output}} ->
          {:error, {:parse_error, reason}}

        {:error, reason} ->
          {:error, {:claude_error, reason}}
      end
    end
  end

  defp build_system_prompt(project_root, nil) do
    case hook(:build_system_prompt) do
      nil ->
        case Foundry.Chat.ContextCache.get_or_build(project_root) do
          {:ok, cached_context} ->
            {:ok, target_project_header(project_root) <> cached_context.prompt}

          {:error, reason} ->
            {:error, {:context_build_failed, reason}}
        end

      fun ->
        fun.(project_root, nil)
    end
  rescue
    e -> {:error, {:context_build_failed, Exception.message(e)}}
  catch
    :exit, reason -> {:error, {:context_build_failed, reason}}
    kind, reason -> {:error, {:context_build_failed, {kind, reason}}}
  end

  defp build_system_prompt(_project_root, %{system_prompt: system_prompt}),
    do: {:ok, system_prompt}

  defp build_run_system_prompt(project_root, retrieval, session_digest, mode, proposal) do
    mode_prompt =
      case mode do
        :change ->
          ChatRetrieval.change_prompt(%{proposal: proposal, tool_results: retrieval.tool_results})

        :ask ->
          """
          ## Ask Mode

          This is an explanation/discovery request. Prefer synthesis from Foundry
          retrieval results before falling back to shell inspection.
          """
      end

    [
      target_project_header(project_root),
      retrieval.cached_context.prompt,
      session_digest_prompt(session_digest),
      ChatRetrieval.tool_prompt(retrieval),
      mode_prompt
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n---\n\n")
  end

  defp project_root do
    :foundry_web
    |> Application.fetch_env!(:igaming_project_root)
    |> Path.expand()
  end

  defp llm_provider do
    Application.get_env(:foundry, :llm_provider, :claude_code)
  end

  defp llm_diagnostics(extra \\ %{}) do
    provider = llm_provider()

    base =
      case provider do
        :codex ->
          %{
            provider: provider,
            sandbox: codex_sandbox(),
            model: codex_model()
          }

        :claude_code ->
          %{
            provider: provider,
            model: claude_code_model()
          }

        :lm_studio ->
          %{
            provider: provider,
            model: lm_studio_model()
          }

        _ ->
          %{provider: provider}
      end

    Map.merge(base, Enum.reject(extra, fn {_key, value} -> is_nil(value) end) |> Map.new())
  end

  defp codex_sandbox do
    :foundry
    |> Application.get_env(:codex, [])
    |> Keyword.get(:sandbox, "workspace-write")
  end

  defp codex_model do
    :foundry
    |> Application.get_env(:codex, [])
    |> Keyword.get(:model)
  end

  defp claude_code_model do
    :foundry
    |> Application.get_env(:claude_code, [])
    |> Keyword.get(:model)
  end

  defp lm_studio_model do
    :foundry
    |> Application.get_env(:lm_studio, [])
    |> Keyword.get(:model)
  end

  defp target_project_header(project_root) do
    """
    # Target Project Boundary

    The target platform for this chat is the reference iGaming project.
    Target project root: #{project_root}

    Treat this directory as the authoritative workspace for project discovery,
    code inspection, and Mix commands.

    ---
    """
  end

  defp load_system_context(socket) do
    project_root = socket.assigns.project_root

    case build_system_prompt(project_root, nil) do
      {:ok, prompt} ->
        socket
        |> assign(:show_system_context, true)
        |> assign(:system_context_prompt, prompt)
        |> assign(:system_context_error, nil)

      {:error, reason} ->
        socket
        |> assign(:show_system_context, true)
        |> assign(:system_context_prompt, nil)
        |> assign(:system_context_error, inspect(reason))
    end
  end

  defp claude_not_installed_message do
    """
    Claude Code is not installed. To enable chat:

    1. Install Claude Code: npm install -g @anthropic-ai/claude-code
    2. Authenticate: claude auth login
    3. Restart Foundry Studio

    Or configure an API key for req_llm instead:
      export ANTHROPIC_API_KEY="sk-ant-..."
      # Then set config :foundry, :llm_provider, :req_llm in config/dev.exs

    See: docs/runbooks/claude_code_unavailable.md
    """
  end

  defp call_codex(messages, run_context) do
    call_codex_stream(messages, fn _event -> :ok end, run_context)
  end

  defp call_codex_stream(messages, on_event, run_context) do
    project_root = project_root()

    with {:ok, system_prompt} <- build_system_prompt(project_root, run_context) do
      config = Application.get_env(:foundry, :codex, [])

      opts = [
        system_prompt: system_prompt,
        timeout_ms: Keyword.get(config, :timeout_ms, 120_000),
        model: Keyword.get(config, :model),
        profile: Keyword.get(config, :profile),
        sandbox: Keyword.get(config, :sandbox, "workspace-write"),
        executable: Keyword.get(config, :executable, "codex"),
        project_root: project_root,
        conversation_window: :all
      ]

      case Foundry.CodexProvider.stream(messages, opts, fn
             {:delta, text} -> on_event.({:delta, text})
             {:trace, event} -> on_event.({:trace, event})
             _event -> :ok
           end) do
        {:ok, text, metadata} ->
          {:ok, text, metadata}

        {:error, :not_installed} ->
          {:ok, codex_not_installed_message()}

        {:error, {:timeout, partial_text, metadata}} ->
          if String.length(partial_text) > 0 do
            {:ok, partial_text, Map.put(metadata || %{}, :partial, true)}
          else
            {:error, :timeout}
          end

        {:error, {:exit_code, code, output}} ->
          {:error, {:codex_exit, code, String.slice(output, 0, 500)}}

        {:error, reason} ->
          {:error, {:codex_error, reason}}
      end
    end
  end

  defp codex_not_installed_message do
    """
    OpenAI Codex CLI is not installed. To enable chat:

    1. Install Codex CLI
    2. Authenticate: codex login
    3. Restart Foundry Studio

    Or configure another provider in config/dev.exs.
    """
  end

  defp call_lm_studio(messages, run_context) do
    call_lm_studio_stream(messages, fn _event -> :ok end, run_context)
  end

  defp call_lm_studio_stream(messages, on_event, run_context) do
    project_root = project_root()

    with {:ok, system_prompt} <- build_system_prompt(project_root, run_context) do
      config = Application.get_env(:foundry, :lm_studio, [])

      lm_messages =
        [%{"role" => "system", "content" => system_prompt}] ++
          Enum.map(messages, fn %{"role" => role, "content" => content} ->
            %{"role" => role, "content" => content}
          end)

      opts = [
        base_url: Keyword.get(config, :base_url, "http://localhost:1234/v1"),
        model: Keyword.get(config, :model, "local-model"),
        timeout_ms: Keyword.get(config, :timeout_ms, 120_000),
        api_key: Keyword.get(config, :api_key, "lm-studio"),
        temperature: Keyword.get(config, :temperature, 0.2)
      ]

      case Foundry.LMStudioProvider.stream(lm_messages, opts, fn
             {:delta, text} -> on_event.({:delta, text})
             _event -> :ok
           end) do
        {:ok, text, metadata} ->
          {:ok, text, metadata}

        {:error, {:timeout, partial_text}} ->
          if String.length(partial_text) > 0 do
            {:ok, partial_text, %{partial: true}}
          else
            {:error, :timeout}
          end

        {:error, reason} ->
          {:error, {:lm_studio_error, reason}}
      end
    end
  end

  defp call_req_llm(messages) do
    prompt =
      messages
      |> Enum.map(fn %{"content" => content, "role" => role} -> "#{role}: #{content}" end)
      |> Enum.join("\n\n")

    model = Application.get_env(:foundry, :copilot_model, "anthropic:claude-sonnet-4-6")

    case Code.ensure_loaded(ReqLLM) do
      {:module, ReqLLM} ->
        try do
          case Code.ensure_loaded(AshAi.ToolLoop) do
            {:module, AshAi.ToolLoop} ->
              ash_ai_call(prompt, model)

            _ ->
              fallback_response(model, prompt)
          end
        rescue
          _e ->
            {:ok,
             "Chat UI works! LLM call would use model: #{model}\n\nPrompt preview: #{String.slice(prompt, 0, 200)}...\n\nConfigure an LLM API key or use a local model to get actual responses."}
        end

      _ ->
        fallback_response(model, prompt)
    end
  end

  defp fallback_response(model, prompt) do
    {:ok,
     "Chat UI is working! LLM call would use model: #{model}\n\nPrompt preview: #{String.slice(prompt, 0, 200)}...\n\nConfigure an LLM API key to get actual responses."}
  end

  defp ash_ai_call(prompt, model) do
    messages = [%{role: "user", content: prompt}]

    case AshAi.ToolLoop.run(messages, model: model, otp_app: :foundry) do
      {:ok, result} ->
        {:ok, extract_assistant_message(result)}

      {:error, reason} ->
        reason_str = inspect(reason)

        if String.contains?(reason_str, ["api_key", "API_KEY", "Failed to build"]) do
          {:ok,
           "LLM call attempted with model: #{model}.\n\nAPI key not configured. Set ANTHROPIC_API_KEY (or equivalent) in your environment to enable actual responses.\n\nThe chat UI and message persistence are working correctly."}
        else
          {:error, reason}
        end
    end
  rescue
    e ->
      {:ok,
       "LLM call attempted with model: #{model}.\n\nError: #{Exception.message(e)}\n\nConfigure an LLM API key to get actual responses."}
  end

  defp extract_assistant_message(results) when is_list(results) do
    results
    |> Enum.find_value(fn
      %{"role" => "assistant", "content" => content} -> content
      %{role: "assistant", content: content} -> content
      _ -> nil
    end) || "No assistant message found."
  end

  defp extract_assistant_message(_),
    do: "Response received (format unrecognized)."

  defp finish_stream(socket, messages, save_result, base_error \\ nil) do
    socket
    |> clear_active_request()
    |> clear_active_task()
    |> assign(:messages, messages)
    |> assign(:loading, false)
    |> assign(:llm_diagnostics, llm_diagnostics())
    |> assign(:error, merge_errors(base_error, save_result))
  end

  defp clear_active_request(socket), do: assign(socket, :active_request_ref, nil)

  defp clear_active_task(socket) do
    case socket.assigns.active_request_task do
      %Task{} = task ->
        Task.shutdown(task, 100)
        Process.demonitor(task.ref, [:flush])
        assign(socket, :active_request_task, nil)

      _ ->
        assign(socket, :active_request_task, nil)
    end
  end

  defp cancel_active_task(socket) do
    socket
    |> clear_active_request()
    |> clear_active_task()
  end

  defp active_task_ref(socket) do
    case socket.assigns.active_request_task do
      %Task{ref: ref} -> ref
      _ -> nil
    end
  end

  defp merge_errors(base_error, :ok), do: base_error

  defp merge_errors(nil, {:error, reason}) do
    persistence_error("Response received but session was not saved", reason)
  end

  defp merge_errors(base_error, {:error, reason}) do
    base_error <>
      "\n\n" <> persistence_error("Response received but session was not saved", reason)
  end

  defp format_request_error({:context_cache_build_failed, _reason}) do
    "Failed to prepare cached Foundry context for this chat request."
  end

  defp format_request_error({:context_build_failed, _reason}) do
    "Failed to build the Foundry project context for this chat request."
  end

  defp format_request_error({:unknown_provider, provider}) do
    "The configured chat provider is not supported: #{provider}."
  end

  defp format_request_error({:codex_exit, _code, output}) do
    cond do
      sandbox_restriction?(output) ->
        "Codex CLI was blocked by its sandbox while trying to run a workspace command. Active sandbox: #{codex_sandbox()}."

      governance_restriction?(output) ->
        "The requested shell action is outside Foundry's permitted command policy for chat."

      provider_tool_restriction?(output) ->
        "Codex CLI rejected the requested tool action before it could run."

      true ->
        "Codex CLI failed while processing the request. #{summarize_output(output)}"
    end
  end

  defp format_request_error({:claude_exit, _code, output}) do
    cond do
      sandbox_restriction?(output) ->
        "Claude Code was blocked by its sandbox while trying to run a workspace command."

      governance_restriction?(output) ->
        "The requested shell action is outside Foundry's permitted command policy for chat."

      provider_tool_restriction?(output) ->
        "Claude Code rejected the requested tool action before it could run."

      true ->
        "Claude Code failed while processing the request. #{summarize_output(output)}"
    end
  end

  defp format_request_error({:lm_studio_error, _reason}) do
    "LM Studio could not complete the request. Check the local model server connection and configuration."
  end

  defp format_request_error({:codex_error, reason}),
    do: "Codex CLI could not complete the request: #{inspect(reason)}"

  defp format_request_error({:claude_error, reason}),
    do: "Claude Code could not complete the request: #{inspect(reason)}"

  defp format_request_error({:parse_error, reason}) do
    "The chat provider returned a response that could not be parsed: #{inspect(reason)}"
  end

  defp format_request_error(:timeout) do
    "The chat provider timed out before returning a complete response."
  end

  defp format_request_error(reason),
    do: "Failed to get response: #{inspect(reason)}"

  defp format_task_shutdown_error(reason),
    do: "Chat request stopped unexpectedly: #{inspect(reason)}"

  defp persistence_error(prefix, reason) do
    details = persistence_reason(reason)

    if show_debug_details?() do
      "#{prefix}. #{details}\nDebug: #{inspect(reason)}"
    else
      "#{prefix}. #{details}"
    end
  end

  defp persistence_reason(:session_store_down),
    do: "The session store is currently unavailable."

  defp persistence_reason(%Ash.Error.Invalid{}),
    do: "The session update was rejected before it could be persisted."

  defp persistence_reason(reason) when is_atom(reason),
    do: "The session history could not be saved (#{reason})."

  defp persistence_reason(_reason),
    do: "The chat response is visible, but it could not be saved to the session history."

  defp show_debug_details? do
    :foundry_web
    |> Application.get_env(FoundryWeb.Endpoint, [])
    |> Keyword.get(:debug_errors, false)
  end

  defp sandbox_restriction?(output) when is_binary(output) do
    String.contains?(String.downcase(output), [
      "sandbox",
      "read-only",
      "landlock",
      "permission denied"
    ])
  end

  defp governance_restriction?(output) when is_binary(output) do
    String.contains?(output, [
      "command_not_permitted",
      "permitted command list",
      "not on the permitted list"
    ])
  end

  defp provider_tool_restriction?(output) when is_binary(output) do
    String.contains?(String.downcase(output), [
      "not allowed",
      "tool denied",
      "tool call failed",
      "approval"
    ])
  end

  defp summarize_output(output) when is_binary(output) do
    trimmed = String.trim(output)

    if trimmed == "" do
      "No additional diagnostics were returned."
    else
      "Details: #{String.slice(trimmed, 0, 180)}"
    end
  end

  defp new_activity_run(message, request_ref, run_context) do
    %{
      id: System.unique_integer([:positive, :monotonic]),
      request_ref: request_ref,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      finished_at: nil,
      status: :running,
      provider: llm_provider(),
      diagnostics: llm_diagnostics(run_context.diagnostics),
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

  defp update_activity_run(socket, request_ref, fun) do
    update(socket, :activity_runs, fn runs ->
      Enum.map(runs, fn
        %{request_ref: ^request_ref} = run -> fun.(run)
        run -> run
      end)
    end)
  end

  defp append_trace_event(run, trace_event) do
    events = [trace_event | run.events] |> Enum.take(250)
    summary = ChatTrace.summarize_run(events)

    run
    |> Map.put(:events, events)
    |> Map.merge(summary)
  end

  defp complete_activity_run(socket, request_ref, response, metadata) do
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

  defp fail_activity_run(socket, request_ref, reason) do
    update_activity_run(socket, request_ref, fn run ->
      run
      |> Map.put(:status, :error)
      |> Map.put(:finished_at, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put(:error, format_request_error(reason))
    end)
  end

  defp summarize_response(response) when is_binary(response) do
    response
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 180)
  end

  defp summarize_response(_response), do: nil

  defp persist_turn_memory(socket, request_ref, response) do
    extracted = SessionMemory.extract(response)
    run = find_activity_run(socket.assigns.activity_runs, request_ref)

    result = %{
      response: extracted.response,
      artifact: nil,
      error: extracted.error
    }

    case extracted.payload do
      nil ->
        result

      payload ->
        metadata = %{
          "mode" => socket.assigns.session_digest |> Map.get("last_mode"),
          "proposal_id" => socket.assigns.session_digest |> Map.get("last_proposal_id"),
          "user_message" => run && run.user_message
        }

        case persist_session_memory(
               socket.assigns.project_root,
               socket.assigns.session_id,
               payload,
               metadata
             ) do
          {:ok, artifact} ->
            %{result | artifact: artifact, error: extracted.error}

          {:error, reason} ->
            %{result | error: reason}
        end
    end
  end

  defp persist_session_memory(project_root, session_id, payload, metadata) do
    case hook(:persist_session_memory) do
      nil ->
        SessionMemory.persist(project_root, session_id, payload, metadata)

      fun ->
        fun.(project_root, session_id, payload, metadata)
    end
  end

  defp maybe_record_memory_trace(socket, _request_ref, %{artifact: nil, error: nil}), do: socket

  defp maybe_record_memory_trace(socket, request_ref, %{artifact: artifact})
       when is_map(artifact) do
    trace_event = %{
      "provider" => "foundry",
      "type" => "foundry.session.finding_saved",
      "phase" => "session",
      "path" => artifact.path,
      "message" => "Saved canonical finding #{artifact.id}",
      "summary" => artifact.summary
    }

    update_activity_run(socket, request_ref, fn run ->
      append_trace_event(run, ChatTrace.normalize(:foundry, trace_event))
    end)
  end

  defp maybe_record_memory_trace(socket, request_ref, %{error: error}) do
    trace_event = %{
      "provider" => "foundry",
      "type" => "foundry.session.finding_save_failed",
      "phase" => "session",
      "message" => "Could not save canonical finding",
      "summary" => inspect(error)
    }

    update_activity_run(socket, request_ref, fn run ->
      append_trace_event(run, ChatTrace.normalize(:foundry, trace_event))
    end)
  end

  defp normalize_session_digest(nil), do: %{}
  defp normalize_session_digest(digest) when is_map(digest), do: digest
  defp normalize_session_digest(_digest), do: %{}

  defp prepare_session_digest(digest, retrieval, mode, proposal) do
    tool_results = retrieval.tool_results

    digest
    |> Map.put("context_fingerprint", retrieval.cached_context.fingerprint)
    |> Map.put("context_cache", Atom.to_string(retrieval.cached_context.cache))
    |> Map.put("last_mode", Atom.to_string(mode))
    |> Map.put(
      "selected_nodes",
      Enum.map(tool_results.module_contexts, & &1.id)
    )
    |> Map.put(
      "recent_documents",
      Enum.map(tool_results.documents, & &1.path)
    )
    |> Map.put(
      "working_summary",
      Map.get(digest, "working_summary") || summarize_working_context(digest)
    )
    |> Map.put("revision_of_proposal_id", Map.get(digest, "revision_of_proposal_id"))
    |> maybe_put_proposal(proposal)
  end

  defp finalized_session_digest(socket, request_ref, response, artifact \\ nil) do
    digest = normalize_session_digest(socket.assigns.session_digest)
    run = find_activity_run(socket.assigns.activity_runs, request_ref)

    recent_conclusions =
      [summarize_response(response) | Map.get(digest, "recent_conclusions", [])]
      |> Enum.reject(&is_nil/1)
      |> Enum.take(5)

    digest
    |> Map.put("recent_conclusions", recent_conclusions)
    |> prepend_recent_finding(artifact)
    |> Map.put("recent_files", if(run, do: run.files, else: []))
    |> Map.put("recent_read_files", if(run, do: run.read_files, else: []))
    |> Map.put("recent_written_files", if(run, do: run.written_files, else: []))
    |> Map.put("recent_tools", if(run, do: run.tools, else: []))
    |> Map.put("recent_token_usage", if(run, do: run.token_usage || %{}, else: %{}))
    |> Map.put(
      "recent_trace_summary",
      if(run,
        do: %{
          "phases" => stringify_atom_keys(run.phase_counts || %{}),
          "provenance" => run.provenance || %{}
        },
        else: %{}
      )
    )
  end

  defp prepend_recent_finding(digest, nil), do: digest

  defp prepend_recent_finding(digest, artifact) do
    recent_findings =
      [format_recent_finding(artifact) | Map.get(digest, "recent_findings", [])]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(5)

    Map.put(digest, "recent_findings", recent_findings)
  end

  defp format_recent_finding(%{title: title, path: path})
       when is_binary(title) and is_binary(path) do
    "#{title} (#{path})"
  end

  defp format_recent_finding(_artifact), do: nil

  defp maybe_put_proposal(digest, nil), do: digest

  defp maybe_put_proposal(digest, proposal) do
    digest
    |> Map.put("last_proposal_id", proposal.id)
    |> Map.put("last_change_class", Atom.to_string(proposal.change_class))
    |> Map.put("active_proposal_id", proposal.id)
    |> Map.put("active_proposal_status", Atom.to_string(proposal.state || :draft))
  end

  defp maybe_attach_message_metadata(message, nil), do: message

  defp maybe_attach_message_metadata(message, run) do
    message
    |> Map.put("mode", Atom.to_string(run.mode))
    |> Map.put("files", run.files || [])
    |> Map.put("read_files", run.read_files || [])
    |> Map.put("written_files", run.written_files || [])
    |> Map.put("tools", run.tools || [])
    |> Map.put("token_usage", run.token_usage || %{})
    |> Map.put("total_tokens", run.total_tokens)
    |> Map.put("provider", to_string(run.provider))
    |> maybe_put_partial(run)
    |> maybe_put_message_proposal(run.proposal)
  end

  defp maybe_put_partial(message, %{metadata: metadata}) when is_map(metadata) do
    if Map.get(metadata, :partial) || Map.get(metadata, "partial") do
      Map.put(message, "partial", true)
    else
      message
    end
  end

  defp maybe_put_partial(message, _run), do: message

  defp maybe_put_message_proposal(message, nil), do: message
  defp maybe_put_message_proposal(message, proposal), do: Map.put(message, "proposal", proposal)

  defp persist_updated_chat(socket) do
    case save_session_state(
           socket.assigns.session_id,
           socket.assigns.messages,
           socket.assigns.session_digest
         ) do
      :ok ->
        socket

      {:error, reason} ->
        assign(socket, :error, persistence_error("Failed to save chat session", reason))
    end
  end

  defp update_latest_proposal_message(messages, proposal_id, status) do
    case latest_proposal_message_index(messages, proposal_id) do
      nil ->
        messages

      index ->
        List.update_at(messages, index, fn message ->
          update_in(message["proposal"], fn
            nil ->
              nil

            proposal when is_map(proposal) ->
              proposal
              |> Map.put(:ui_status, status)
              |> Map.put("ui_status", status)
          end)
        end)
    end
  end

  defp latest_proposal_message_index(messages, proposal_id) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {message, index} ->
      proposal = message["proposal"]
      proposal_value = proposal && (proposal[:id] || proposal["id"])

      if message["role"] == "assistant" and to_string(proposal_value) == proposal_id, do: index
    end)
  end

  defp active_proposal_overlay(messages, proposal_id) do
    messages
    |> find_proposal(proposal_id)
    |> case do
      nil ->
        %{}

      proposal ->
        get_in(proposal, [:preview, :graph_overlay]) ||
          get_in(proposal, ["preview", "graph_overlay"]) || %{}
    end
  end

  defp active_proposal_delta(messages, proposal_id) do
    overlay = active_proposal_overlay(messages, proposal_id)

    %{
      nodes_added: overlay[:nodes_added] || overlay["nodes_added"] || [],
      nodes_modified: overlay[:nodes_modified] || overlay["nodes_modified"] || [],
      edges_added: overlay[:edges_added] || overlay["edges_added"] || [],
      edges_removed: overlay[:edges_removed] || overlay["edges_removed"] || []
    }
  end

  defp proposal_file_preview_payload(messages, proposal_id, path) do
    with proposal when is_map(proposal) <- find_proposal(messages, proposal_id),
         files when is_list(files) <-
           get_in(proposal, [:preview, :files]) || get_in(proposal, ["preview", "files"]),
         file when is_map(file) <-
           Enum.find(files, fn preview_file ->
             (preview_file[:path] || preview_file["path"]) == path
           end) do
      %{
        proposal_id: proposal_id,
        path: path,
        status: file[:status] || file["status"] || :modified,
        diff: file[:diff] || file["diff"] || "",
        content: file[:full_content] || file["full_content"] || "",
        added_lines: file[:added_lines] || file["added_lines"] || 0,
        removed_lines: file[:removed_lines] || file["removed_lines"] || 0
      }
    end
  end

  defp find_proposal(messages, proposal_id) do
    Enum.find_value(messages, fn
      %{"proposal" => proposal} when is_map(proposal) ->
        if to_string(proposal[:id] || proposal["id"]) == proposal_id, do: proposal

      _ ->
        nil
    end)
  end

  defp stringify_atom_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp find_activity_run(activity_runs, request_ref) do
    Enum.find(activity_runs, &(&1.request_ref == request_ref))
  end

  defp session_digest_prompt(session_digest) do
    """
    ## Session Memory

    ```json
    #{Jason.encode!(session_digest, pretty: true)}
    ```
    """
  end

  defp classify_mode(message) do
    lowered = String.downcase(message)

    if String.contains?(lowered, [
         "fix",
         "implement",
         "edit",
         "update",
         "change",
         "create",
         "add",
         "remove",
         "delete",
         "rename",
         "refactor",
         "migrate",
         "write test",
         "write tests"
       ]) do
      :change
    else
      :ask
    end
  end

  defp parse_chat_view("trace"), do: :trace
  defp parse_chat_view("session"), do: :session
  defp parse_chat_view(_view), do: :conversation

  defp build_session_summary(digest, messages, activity_runs) do
    recent_assistant_points =
      messages
      |> Enum.filter(&(&1["role"] == "assistant"))
      |> Enum.map(&String.trim(&1["content"] || ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(-3)
      |> Enum.map(&String.slice(&1, 0, 220))

    recent_reads = digest |> Map.get("recent_read_files", []) |> Enum.take(8)
    recent_writes = digest |> Map.get("recent_written_files", []) |> Enum.take(8)
    latest_run = List.first(activity_runs || [])

    summary =
      [
        summarize_working_context(digest),
        if(recent_assistant_points != [],
          do: "Recent outcomes: " <> Enum.join(recent_assistant_points, " | ")
        ),
        if(recent_reads != [], do: "Recent reads: " <> Enum.join(recent_reads, ", ")),
        if(recent_writes != [], do: "Recent writes: " <> Enum.join(recent_writes, ", ")),
        if(latest_run && latest_run.tools != [],
          do: "Recent tools: " <> Enum.join(Enum.take(latest_run.tools, 6), ", ")
        )
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")

    digest
    |> Map.put("working_summary", summary)
    |> Map.put("summary_updated_at", DateTime.utc_now() |> DateTime.to_iso8601())
  end

  defp summarize_working_context(digest) do
    [
      digest["last_mode"] && "Mode #{digest["last_mode"]}",
      digest["last_proposal_id"] && "proposal #{digest["last_proposal_id"]}",
      digest["context_fingerprint"] && "context #{digest["context_fingerprint"]}",
      digest["recent_conclusions"] |> List.wrap() |> List.first()
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" | ")
  end

  defp normalize_usage(metadata) when is_map(metadata) do
    usage = Map.get(metadata, :usage) || Map.get(metadata, "usage") || %{}

    %{
      input_tokens:
        usage[:input_tokens] || usage["input_tokens"] || usage[:prompt_tokens] ||
          usage["prompt_tokens"],
      output_tokens:
        usage[:output_tokens] || usage["output_tokens"] || usage[:completion_tokens] ||
          usage["completion_tokens"],
      total_tokens:
        usage[:total_tokens] || usage["total_tokens"] || usage[:total] || usage["total"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_usage(_metadata), do: %{}

  defp usage_total(%{total_tokens: total}) when is_integer(total), do: total

  defp usage_total(usage) when is_map(usage) do
    input = Map.get(usage, :input_tokens)
    output = Map.get(usage, :output_tokens)

    if is_integer(input) or is_integer(output) do
      (input || 0) + (output || 0)
    end
  end

  defp usage_total(_usage), do: nil

  defp hook(key) do
    :foundry_web
    |> Application.get_env(:chat_live_hooks, [])
    |> Keyword.get(key)
  end

  defp project_fingerprint do
    project_root()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  defp maybe_load_active_session_into_chat(socket, nil), do: socket

  defp maybe_load_active_session_into_chat(socket, session_id) do
    sessions_by_id = socket.assigns.sessions_by_id

    case Map.get(sessions_by_id, session_id) do
      nil ->
        socket

      session ->
        messages = session["messages"] || []
        session_digest = session["session_digest"] || %{}

        socket
        |> assign(:session_id, session_id)
        |> assign(:messages, messages)
        |> assign(:session_digest, session_digest)
        |> assign(:activity_runs, [])
        |> assign(:selected_activity_run_id, nil)
        |> assign(:loading, false)
        |> assign(:error, nil)
        |> assign(:active_request_ref, nil)
    end
  end

  defp switch_to_session(socket, session_id) do
    socket
    |> assign(:session_id, session_id)
    |> assign(:messages, [])
    |> assign(:session_digest, %{})
    |> assign(:activity_runs, [])
    |> assign(:selected_activity_run_id, nil)
    |> assign(:loading, false)
    |> assign(:error, nil)
    |> assign(:active_request_ref, nil)
  end

  defp push_workspace_state(socket) do
    push_event(socket, "chat_workspace_updated", %{
      open_session_ids: socket.assigns.open_session_ids,
      active_session_id: socket.assigns.active_session_id
    })
  end
end
