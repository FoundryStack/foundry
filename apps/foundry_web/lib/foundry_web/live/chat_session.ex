defmodule FoundryWeb.ChatSession do
  @moduledoc """
  Foundry chat live view — thin orchestration layer.

  This live view delegates to two specialized modules:

  1. **PhoenixLLMChat.Core** — generic streaming lifecycle
     - Message submission and basic state management
     - Stream delta accumulation, done/error/trace handling
     - Response finalization and message persistence

  2. **FoundryWeb.ChatSessionDomainLogic** — Foundry-specific concerns
     - Proposal/change management (apply, revise, cancel)
     - Activity run tracking with ChatTrace integration
     - Session memory and digest building
     - Retrieval context preparation and system prompts
     - Message formatting and metadata attachment
     - Session persistence via FileSessionStore

  ChatSession is the event dispatcher: it routes incoming events to the appropriate
  handler (Core or DomainLogic) and updates socket state accordingly. This keeps
  the live view code focused on orchestration rather than implementation details.

  ## Architecture

  - **mount/2**: Initialize socket with Core + Foundry state
  - **handle_event**: Route to Core for simple ops (send_message, update_chat_input),
    route to DomainLogic for complex ops (proposals, workspace management)
  - **handle_info**: Dispatch streaming events from background LLM task, update
    activity runs and messages based on accumulating deltas
  - **Helpers**: Provider selection, error formatting, provider-specific call logic,
    and session workspace management

  All Foundry domain logic lives in ChatSessionDomainLogic. ChatSession orchestrates.
  """

  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  require Ash.Query
  require Logger

  alias Foundry.Chat.FileSessionStore
  alias Foundry.Chat.MessageClassifier
  alias PhoenixLLMChat.Core
  alias FoundryWeb.ChatModelCatalog
  alias FoundryWeb.ChatSessionDomainLogic, as: DomainLogic
  alias FoundryWeb.ChatConfig
  alias FoundryWeb.ChatProviders

  # --- Mount ---

  def mount(socket, session) do
    session_id = Map.get(session, "chat_session_id", Ecto.UUID.generate())
    model_catalog = ChatModelCatalog.catalog()

    {loaded_session, messages, session_digest, load_error} =
      case DomainLogic.load_session(session_id) do
        {:ok, chat_session} when not is_nil(chat_session) ->
          {chat_session, chat_session["messages"] || [], chat_session["session_digest"] || %{},
           nil}

        {:ok, nil} ->
          {nil, [], %{}, nil}

        {:error, reason} ->
          {nil, [], %{}, persistence_error("Failed to load chat session", reason)}
      end

    selected_model =
      (loaded_session && loaded_session["selected_model_id"]) ||
        Map.get(session, "selected_model_id")
        |> resolve_selected_model(model_catalog)

    project_root =
      case Map.fetch(socket.assigns, :project_root) do
        {:ok, existing_project_root} -> existing_project_root
        :error -> ChatConfig.project_root()
      end

    socket =
      socket
      |> Core.mount(session)
      |> assign(:session_id, session_id)
      |> assign(:messages, messages)
      |> assign(:session_digest, session_digest)
      |> assign(:error, load_error)
      |> assign(:active_request_ref, nil)
      |> assign(:active_request_task, nil)
      |> assign(:pending_messages, [])
      |> assign(:project_root, project_root)
      |> assign(:show_system_context, false)
      |> assign(:system_context_prompt, nil)
      |> assign(:system_context_error, nil)
      |> assign(:model_catalog, model_catalog)
      |> assign(:selected_model, selected_model)
      |> assign(:project_fingerprint, project_fingerprint())
      |> assign(:llm_provider, selected_model && selected_model.provider)
      |> assign(:llm_diagnostics, llm_diagnostics(selected_model))
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

  # --- Workspace / Session Tab Events ---

  def handle_event(
        "chat_workspace_hydrate",
        %{"open_session_ids" => open_ids, "active_session_id" => active_id} = params,
        socket
      ) do
    open_ids = Enum.filter(open_ids, &is_binary/1)
    workspace_id = Map.get(params, "workspace_id") || socket.assigns.workspace_id
    project_fp = socket.assigns.project_fingerprint

    sessions_by_id =
      case open_ids do
        [] ->
          list_persisted_sessions(workspace_id, project_fp)

        _ ->
          Enum.reduce(open_ids, %{}, fn id, acc ->
            case FileSessionStore.load(id) do
              {:ok, session} when is_map(session) -> Map.put(acc, id, session)
              _ -> acc
            end
          end)
      end

    valid_open_ids =
      case open_ids do
        [] -> Map.keys(sessions_by_id)
        _ -> Enum.filter(open_ids, &Map.has_key?(sessions_by_id, &1))
      end

    {socket, valid_open_ids, sessions_by_id, active_id} =
      if valid_open_ids == [] do
        create_session_in_workspace(socket, workspace_id)
      else
        active_id =
          cond do
            active_id in valid_open_ids -> active_id
            valid_open_ids != [] -> List.first(valid_open_ids)
            true -> nil
          end

        {assign(socket, :workspace_id, workspace_id), valid_open_ids, sessions_by_id, active_id}
      end

    socket =
      socket
      |> assign(:workspace_id, workspace_id)
      |> assign(:open_session_ids, valid_open_ids)
      |> assign(:active_session_id, active_id)
      |> assign(:sessions_by_id, sessions_by_id)
      |> maybe_load_active_session_into_chat(active_id)
      |> push_workspace_state()

    {:noreply, socket}
  end

  def handle_event("chat_workspace_hydrate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("chat_session_new", _params, socket) do
    {socket, open_ids, sessions_by_id, session_id} =
      create_session_in_workspace(socket, socket.assigns.workspace_id)

    socket =
      socket
      |> assign(:open_session_ids, open_ids)
      |> assign(:active_session_id, session_id)
      |> assign(:sessions_by_id, sessions_by_id)
      |> switch_to_session(session_id)
      |> push_event("chat:scroll_to_bottom", %{force: true})
      |> push_workspace_state()

    {:noreply, socket}
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
        |> push_workspace_state()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("chat_session_close", %{"id" => id}, socket) do
    open_ids = Enum.filter(socket.assigns.open_session_ids, &(&1 != id))

    active_id =
      if socket.assigns.active_session_id == id do
        List.first(open_ids)
      else
        socket.assigns.active_session_id
      end

    socket =
      socket
      |> assign(:open_session_ids, open_ids)
      |> assign(:active_session_id, active_id)
      |> maybe_load_active_session_into_chat(active_id)
      |> push_workspace_state()

    {:noreply, socket}
  end

  def handle_event("chat_session_rename", %{"id" => id, "title" => title}, socket) do
    case DomainLogic.rename_session(id, title) do
      {:ok, session} ->
        sessions_by_id = Map.put(socket.assigns.sessions_by_id, id, session)
        {:noreply, assign(socket, :sessions_by_id, sessions_by_id)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("chat_session_delete", %{"id" => id}, socket) do
    case FileSessionStore.delete(id) do
      :ok ->
        sessions_by_id = Map.delete(socket.assigns.sessions_by_id, id)
        open_ids = Enum.filter(socket.assigns.open_session_ids, &(&1 != id))

        active_id =
          if socket.assigns.active_session_id == id do
            List.first(open_ids)
          else
            socket.assigns.active_session_id
          end

        socket =
          socket
          |> assign(:sessions_by_id, sessions_by_id)
          |> assign(:open_session_ids, open_ids)
          |> assign(:active_session_id, active_id)
          |> maybe_load_active_session_into_chat(active_id)
          |> push_workspace_state()

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # --- Chat Events ---

  def handle_event("toggle_system_context", _params, socket) do
    {:noreply, update(socket, :show_system_context, &(!&1))}
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      if socket.assigns.active_request_ref do
        queued_message = build_user_message(message, "queued")

        {:noreply,
         socket
         |> update(:messages, &(&1 ++ [queued_message]))
         |> update(:pending_messages, &(&1 ++ [queued_message]))
         |> assign(:input, "")}
      else
        case MessageClassifier.classify_proposal_command(
               message,
               socket.assigns.session_digest || %{}
             ) do
          {:proposal_action, action, proposal_id} ->
            user_msg = %{
              "role" => "user",
              "content" => message,
              "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
            }

            socket =
              socket
              |> update(:messages, &(&1 ++ [user_msg]))
              |> assign(:input, "")

            handle_event(action, %{"id" => proposal_id}, socket)

          :not_a_proposal_command ->
            with {:ok, run_context} <- build_run_context(socket, message) do
              user_msg = build_user_message(message, "sending")

              request_ref = make_ref()

              activity_run =
                DomainLogic.create_activity_run(
                  message,
                  request_ref,
                  run_context,
                  fn -> socket.assigns.selected_model.provider end,
                  fn extra -> llm_diagnostics(socket.assigns.selected_model, extra) end
                )

              persisted_messages = socket.assigns.messages ++ [user_msg]

              assistant_msg = %{
                "role" => "assistant",
                "content" => "",
                "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
              }

              messages = persisted_messages ++ [assistant_msg]

              case DomainLogic.save_session_state(
                     socket.assigns.session_id,
                     persisted_messages,
                     run_context.session_digest,
                     socket.assigns.workspace_id,
                     socket.assigns.project_fingerprint,
                     socket.assigns.selected_model
                   ) do
                :ok ->
                  task = start_llm_stream(request_ref, persisted_messages, self(), run_context)

                  socket =
                    socket
                    |> cancel_active_task()
                    |> assign(:messages, messages)
                    |> assign(:session_digest, run_context.session_digest)
                    |> assign(:input, "")
                    |> assign(:chat_loading, true)
                    |> assign(:error, nil)
                    |> assign(:active_request_ref, request_ref)
                    |> assign(:active_request_task, task)
                    |> assign(
                      :llm_diagnostics,
                      llm_diagnostics(socket.assigns.selected_model, run_context.diagnostics)
                    )
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
                   |> assign(:chat_loading, false)}
              end
            else
              {:error, reason} ->
                Logger.error("build_run_context failed: #{inspect(reason)}")
                {:noreply, assign(socket, :error, format_request_error(reason))}
            end
        end
      end
    end
  end

  def handle_event("cancel_message", _params, socket) do
    socket = cancel_active_task(socket)
    {:noreply, assign(socket, :chat_loading, false)}
  end

  def handle_event("update_chat_input", params, socket) do
    message = params["value"] || ""
    {:noreply, assign(socket, :input, message)}
  end

  def handle_event("set_chat_model", %{"model" => model_id}, socket) do
    selected_model =
      model_id
      |> resolve_selected_model(socket.assigns.model_catalog)
      |> case do
        nil -> socket.assigns.selected_model
        entry -> entry
      end

    if ChatModelCatalog.available?(selected_model) do
      socket =
        socket
        |> assign(:selected_model, selected_model)
        |> assign(:llm_provider, selected_model.provider)
        |> assign(:llm_diagnostics, llm_diagnostics(selected_model))
        |> persist_session_selection()

      {:noreply, socket}
    else
      {:noreply, socket}
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
    {:noreply, assign(socket, :last_session_summary_at, DateTime.utc_now() |> DateTime.to_iso8601())}
  end

  # --- Proposal Events ---

  def handle_event("proposal_apply", %{"id" => proposal_id}, socket) do
    socket = DomainLogic.handle_proposal_apply(socket, proposal_id)
    {:noreply, socket}
  end

  def handle_event("proposal_revise", %{"id" => proposal_id}, socket) do
    socket = DomainLogic.handle_proposal_revise(socket, proposal_id)
    {:noreply, socket}
  end

  def handle_event("proposal_cancel", %{"id" => proposal_id}, socket) do
    socket = DomainLogic.handle_proposal_cancel(socket, proposal_id)
    {:noreply, socket}
  end

  def handle_event(
        "open_proposal_file_preview",
        %{"proposal_id" => proposal_id, "path" => path},
        socket
      ) do
    socket =
      case DomainLogic.get_proposal_file_preview(socket, proposal_id, path) do
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

  # --- Streaming Events ---

  def handle_info({:llm_stream_delta, request_ref, delta}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      socket =
        socket
        |> update(:messages, &append_to_streaming_response(&1, delta))
        |> DomainLogic.update_activity_run(request_ref, fn run ->
          Map.update(run, :stream_cursor, String.length(delta), &(&1 + String.length(delta)))
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_done, request_ref, response, metadata}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      memory_result = DomainLogic.persist_turn_memory(socket, request_ref, response)

      socket =
        socket
        |> DomainLogic.complete_activity_run(request_ref, memory_result.response, metadata)
        |> DomainLogic.maybe_record_memory_trace(request_ref, memory_result)
        |> maybe_apply_session_title(memory_result.session_title)

      run = DomainLogic.find_activity_run(socket.assigns.activity_runs, request_ref)
      messages = finalize_streaming_response(socket.assigns.messages, memory_result.response, run)

      digest =
        DomainLogic.finalize_session_digest(
          socket,
          request_ref,
          memory_result.response,
          memory_result.artifact,
          true
        )

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:chat_loading, false)
        |> assign(:session_digest, digest)
        |> clear_active_request()

      Task.Supervisor.async_nolink(FoundryWeb.ChatTaskSupervisor, fn ->
        DomainLogic.save_session_state(
          socket.assigns.session_id,
          messages,
          digest,
          socket.assigns.workspace_id,
          socket.assigns.project_fingerprint,
          socket.assigns.selected_model
        )
      end)

      socket = process_pending_messages(socket)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_trace, request_ref, raw_event}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      {:noreply,
       DomainLogic.update_activity_run(socket, request_ref, fn run ->
         DomainLogic.append_trace_event_to_run(run, raw_event)
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_error, request_ref, reason}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      messages = drop_empty_streaming_response(socket.assigns.messages)
      digest = DomainLogic.finalize_session_digest(socket, request_ref, nil, nil, false)

      socket =
        socket
        |> DomainLogic.fail_activity_run(request_ref, reason, &format_request_error/1)
        |> assign(:messages, messages)
        |> assign(:chat_loading, false)
        |> assign(:session_digest, digest)
        |> clear_active_request()
        |> assign(:error, format_request_error(reason))

      Task.Supervisor.async_nolink(FoundryWeb.ChatTaskSupervisor, fn ->
        DomainLogic.save_session_state(
          socket.assigns.session_id,
          messages,
          digest,
          socket.assigns.workspace_id,
          socket.assigns.project_fingerprint,
          socket.assigns.selected_model
        )
      end)

      socket = process_pending_messages(socket)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({ref, _result}, socket) when is_reference(ref) do
    {:noreply, socket}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, socket) do
    if ref == socket.assigns.active_request_task && ref != nil do
      Logger.warning("Task process died: pid=#{inspect(pid)}, reason=#{inspect(reason)}")
      messages = drop_empty_streaming_response(socket.assigns.messages)

      digest =
        DomainLogic.finalize_session_digest(
          socket,
          socket.assigns.active_request_ref,
          nil,
          nil,
          false
        )

      socket =
        socket
        |> DomainLogic.fail_activity_run(
          socket.assigns.active_request_ref,
          reason,
          &format_request_error/1
        )
        |> assign(:messages, messages)
        |> assign(:chat_loading, false)
        |> assign(:session_digest, digest)
        |> clear_active_request()
        |> assign(:error, format_task_shutdown_error(reason))

      Task.Supervisor.async_nolink(FoundryWeb.ChatTaskSupervisor, fn ->
        DomainLogic.save_session_state(
          socket.assigns.session_id,
          messages,
          digest,
          socket.assigns.workspace_id,
          socket.assigns.project_fingerprint,
          socket.assigns.selected_model
        )
      end)

      socket = process_pending_messages(socket)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, _socket), do: :unhandled

  # --- Helper Functions ---

  defp build_run_context(socket, message) do
    DomainLogic.build_run_context(
      socket,
      message,
      fn key -> ChatConfig.hook(key) end,
      &DomainLogic.normalize_session_digest/1,
      &build_run_system_prompt/5,
      socket.assigns.project_root
    )
    |> case do
      {:ok, run_context} ->
        {:ok, Map.put(run_context, :selected_model, socket.assigns.selected_model)}

      other ->
        other
    end
  end

  defp start_llm_stream(request_ref, messages, live_view_pid, run_context) do
    Task.Supervisor.async_nolink(FoundryWeb.ChatTaskSupervisor, fn ->
      Enum.each(run_context.trace_events, fn event ->
        send(live_view_pid, {:llm_stream_trace, request_ref, event})
      end)

      result =
        call_llm_stream(
          messages,
          fn event ->
            send(live_view_pid, format_stream_event(request_ref, event))
          end,
          run_context
        )

      case result do
        {:ok, text} ->
          send(live_view_pid, {:llm_stream_done, request_ref, text, %{}})

        {:ok, text, metadata} ->
          send(live_view_pid, {:llm_stream_done, request_ref, text, metadata})

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
    update_last_assistant_message(
      messages,
      &Map.update(&1, "content", delta, fn c -> c <> delta end)
    )
  end

  defp finalize_streaming_response(messages, "", _run), do: messages

  defp finalize_streaming_response(messages, response, run) do
    messages
    |> mark_latest_user_message_complete()
    |> update_last_assistant_message(fn msg ->
      # Prefer existing streamed content so text_cursor positions remain valid.
      # Fall back to the cleaned response only if streamed content is absent.
      existing = msg["content"] || ""
      content = if existing != "", do: strip_hidden_tail(existing), else: response
      Map.put(msg, "content", content)
    end)
    |> update_last_assistant_message(&DomainLogic.maybe_attach_message_metadata(&1, run))
  end

  @hidden_block_regex ~r/\s*```(?:foundry-memory|foundry-session)\s*\{.*?\}\s*```\s*$/s
  defp strip_hidden_tail(content) do
    Regex.replace(@hidden_block_regex, content, "")
  end

  defp drop_empty_streaming_response(messages) do
    case latest_streaming_assistant_index(messages) do
      nil ->
        messages

      index ->
        List.delete_at(messages, index)
    end
  end

  defp update_last_assistant_message(messages, fun) do
    case latest_assistant_index(messages) do
      nil -> messages
      index -> List.update_at(messages, index, fun)
    end
  end

  defp process_pending_messages(socket) do
    if Enum.empty?(socket.assigns.pending_messages) do
      socket
    else
      [next_pending | rest] = socket.assigns.pending_messages

      socket =
        socket
        |> assign(:pending_messages, rest)
        |> update(:messages, &mark_message_status(&1, next_pending["id"], "sending"))

      dispatch_queued_message(socket, next_pending)
    end
  end

  defp clear_active_request(socket) do
    socket
    |> assign(:active_request_ref, nil)
    |> assign(:active_request_task, nil)
  end

  defp maybe_apply_session_title(socket, nil), do: socket

  defp maybe_apply_session_title(socket, title) do
    session_ids =
      [socket.assigns.session_id, socket.assigns.active_session_id]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if session_ids == [] or session_label_locked?(socket) do
      socket
    else
      case DomainLogic.rename_session(List.first(session_ids), title) do
        {:ok, session} ->
          update(socket, :sessions_by_id, fn sessions ->
            Enum.reduce(session_ids, sessions, fn session_id, acc ->
              existing = Map.get(acc, session_id, %{})
              Map.put(acc, session_id, Map.merge(existing, session))
            end)
          end)

        {:error, _reason} ->
          socket
      end
    end
  end

  defp session_label_locked?(socket) do
    digest = socket.assigns.session_digest || %{}
    title = get_in(socket.assigns.sessions_by_id, [socket.assigns.session_id, "title"])

    digest["session_label_locked"] == true or (is_binary(title) and title != "New session")
  end

  defp clear_active_task(socket) do
    task = socket.assigns.active_request_task

    if task do
      try do
        Task.shutdown(task, :brutal_kill)
      rescue
        _ -> :ok
      end
    end

    socket
  end

  defp cancel_active_task(socket) do
    if socket.assigns.active_request_task do
      clear_active_task(socket)
    else
      socket
    end
  end

  # --- Error Formatting ---

  defp format_request_error({:context_cache_build_failed, _reason}) do
    "Failed to build context cache. Check project root and filesystem permissions."
  end

  defp format_request_error({:context_build_failed, _reason}) do
    "Failed to build retrieval context. Check connectivity and project configuration."
  end

  defp format_request_error({:unknown_provider, provider}) do
    "Unknown LLM provider: #{provider}"
  end

  defp format_request_error({:codex_exit, _code, output}) do
    "Claude Code exited with error:\n\n#{summarize_output(output)}"
  end

  defp format_request_error({:claude_exit, _code, output}) do
    error_output = summarize_output(output)

    cond do
      sandbox_restriction?(error_output) ->
        "Claude Code request blocked due to sandbox restrictions."

      governance_restriction?(error_output) ->
        "Request blocked by governance policy. This may indicate a security concern."

      provider_tool_restriction?(error_output) ->
        "Claude Code request blocked due to tool restrictions."

      true ->
        "Claude Code exited with error:\n\n#{error_output}"
    end
  end

  defp format_request_error({:lm_studio_error, _reason}) do
    "LM Studio connection failed. Ensure LM Studio is running and accessible."
  end

  defp format_request_error({:codex_error, reason}),
    do: "Claude Code error: #{inspect(reason)}"

  defp format_request_error({:claude_error, reason}),
    do: "Claude error: #{inspect(reason)}"

  defp format_request_error({:parse_error, reason}) do
    "Failed to parse LLM response: #{inspect(reason)}"
  end

  defp format_request_error(:timeout) do
    "Request timed out. Try again or adjust your query."
  end

  defp format_request_error(reason),
    do: "Error: #{inspect(reason)}"

  defp format_task_shutdown_error(reason),
    do: "Task interrupted: #{inspect(reason)}"

  defp persistence_error(prefix, reason) do
    "#{prefix}: #{persistence_reason(reason)}"
  end

  defp persistence_reason(:session_store_down),
    do: "Session store unavailable"

  defp persistence_reason(%Ash.Error.Invalid{}),
    do: "Invalid session data"

  defp persistence_reason(reason) when is_atom(reason),
    do: Atom.to_string(reason)

  defp persistence_reason(_reason),
    do: "Unknown error"

  defp sandbox_restriction?(output) when is_binary(output) do
    String.contains?(output, [
      "sandbox",
      "SecurityException",
      "permission denied"
    ])
  end

  defp governance_restriction?(output) when is_binary(output) do
    String.contains?(output, [
      "governance",
      "policy",
      "restricted"
    ])
  end

  defp provider_tool_restriction?(output) when is_binary(output) do
    String.contains?(output, [
      "tool not allowed",
      "tool_name_mismatch"
    ])
  end

  defp summarize_output(output) when is_binary(output) do
    if ChatConfig.show_debug_details?() do
      output
    else
      output
      |> String.split("\n")
      |> Enum.take(5)
      |> Enum.join("\n")
    end
  end

  # --- Provider Selection ---

  defp call_llm_stream(messages, on_event, run_context) do
    case ChatConfig.hook(:call_llm_stream) do
      fun when is_function(fun, 3) -> fun.(messages, on_event, run_context)
      fun when is_function(fun, 2) -> fun.(messages, on_event)
      _ -> ChatProviders.call_stream(messages, on_event, run_context)
    end
  end

  # --- System Prompt Building ---

  defp build_run_system_prompt(project_root, retrieval, session_digest, mode, proposal) do
    base_prompt = """
    # Target Project Boundary

    The target platform for this chat is the reference iGaming project.
    Target project root: #{project_root}

    Treat this directory as the authoritative workspace for project discovery,
    code inspection, and Mix commands.

    ---
    """

    case mode do
      :change ->
        base_prompt <> "\n" <> build_proposal_prompt(proposal, retrieval, session_digest)

      _ ->
        base_prompt <> "\n" <> build_conversation_prompt(session_digest)
    end
  end

  defp build_proposal_prompt(proposal, retrieval, _session_digest) do
    """
    # Proposal Generation Mode

    You are assisting with code changes. Based on user intent and codebase analysis,
    generate a structured proposal with:
    - List of modified/created files
    - Code diffs or content
    - Rationale for changes
    - Potential side effects

    Proposal: #{(proposal && proposal.title) || "TBD"}
    Context: #{(retrieval && retrieval.tool_results && map_size(retrieval.tool_results)) || 0} relevant files analyzed
    """
  end

  defp build_conversation_prompt(session_digest) do
    """
    # Conversation Mode

    You are a code assistant helping the developer understand and explore the codebase.
    Provide clear, concise explanations with code examples when relevant.

    Session context: #{(session_digest && map_size(session_digest)) || 0} entries
    """
  end

  # --- Provider Utilities ---

  defp llm_diagnostics(selected_model, extra \\ %{}) do
    provider = selected_model && selected_model.provider
    model = selected_model && selected_model.model_id

    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      provider: provider,
      model: model,
      node: Node.self(),
      extra: extra
    }
  end

  # --- Session Helpers ---

  defp parse_chat_view("trace"), do: :trace
  defp parse_chat_view("session"), do: :session
  defp parse_chat_view(_view), do: :conversation

  defp project_fingerprint do
    ChatConfig.project_root()
    |> File.stat!()
    |> then(fn %{mtime: mtime} -> :erlang.phash2(mtime) end)
  rescue
    _ -> nil
  end

  defp maybe_load_active_session_into_chat(socket, nil), do: socket

  defp maybe_load_active_session_into_chat(socket, session_id) do
    case DomainLogic.load_session(session_id) do
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
    end
  end

  defp switch_to_session(socket, session_id) do
    maybe_load_active_session_into_chat(socket, session_id)
  end

  defp push_workspace_state(socket) do
    push_event(socket, "workspace:state", %{
      workspace_id: socket.assigns.workspace_id,
      active_session_id: socket.assigns.active_session_id,
      open_session_ids: socket.assigns.open_session_ids,
      session_count: map_size(socket.assigns.sessions_by_id || %{})
    })
  end

  defp list_persisted_sessions(workspace_id, project_fingerprint) do
    with {:ok, sessions} <- FileSessionStore.list(workspace_id, project_fingerprint) do
      Map.new(sessions, &{&1["id"], &1})
    else
      _ -> %{}
    end
  end

  defp create_session_in_workspace(socket, workspace_id) do
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

  defp resolve_selected_model(nil, model_catalog),
    do: ChatModelCatalog.get(model_catalog, ChatModelCatalog.default_model_id(model_catalog))

  defp resolve_selected_model(model_id, model_catalog) do
    ChatModelCatalog.get(model_catalog, model_id) ||
      ChatModelCatalog.get(model_catalog, ChatModelCatalog.default_model_id(model_catalog))
  end

  defp build_user_message(message, status) do
    %{
      "id" => Ecto.UUID.generate(),
      "role" => "user",
      "content" => message,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "delivery_status" => status
    }
  end

  defp dispatch_queued_message(socket, queued_message) do
    with {:ok, run_context} <- build_run_context(socket, queued_message["content"]) do
      request_ref = make_ref()

      activity_run =
        DomainLogic.create_activity_run(
          queued_message["content"],
          request_ref,
          run_context,
          fn -> socket.assigns.selected_model.provider end,
          fn extra -> llm_diagnostics(socket.assigns.selected_model, extra) end
        )

      persisted_messages =
        socket.assigns.messages
        |> messages_through(queued_message["id"])
        |> Enum.map(fn
          %{"role" => "user"} = message ->
            if message["id"] == queued_message["id"] do
              Map.put(message, "delivery_status", "sending")
            else
              message
            end

          message ->
            message
        end)

      assistant_msg = %{
        "role" => "assistant",
        "content" => "",
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      messages =
        socket.assigns.messages
        |> update_message(queued_message["id"], &Map.put(&1, "delivery_status", "sending"))
        |> insert_after_message(queued_message["id"], assistant_msg)

      case DomainLogic.save_session_state(
             socket.assigns.session_id,
             persisted_messages,
             run_context.session_digest,
             socket.assigns.workspace_id,
             socket.assigns.project_fingerprint,
             socket.assigns.selected_model
           ) do
        :ok ->
          task = start_llm_stream(request_ref, persisted_messages, self(), run_context)

          socket
          |> assign(:messages, messages)
          |> assign(:session_digest, run_context.session_digest)
          |> assign(:chat_loading, true)
          |> assign(:error, nil)
          |> assign(:active_request_ref, request_ref)
          |> assign(:active_request_task, task)
          |> assign(
            :llm_diagnostics,
            llm_diagnostics(socket.assigns.selected_model, run_context.diagnostics)
          )
          |> assign(
            :activity_runs,
            [activity_run | socket.assigns.activity_runs] |> Enum.take(12)
          )
          |> assign(:selected_activity_run_id, activity_run.id)
          |> push_event("chat:scroll_to_bottom", %{force: true})

        {:error, reason} ->
          assign(socket, :error, persistence_error("Failed to save chat session", reason))
      end
    else
      {:error, reason} ->
        assign(socket, :error, format_request_error(reason))
    end
  end

  defp messages_through(messages, message_id) do
    {items, _done?} =
      Enum.reduce_while(messages, {[], false}, fn message, {acc, _done?} ->
        next = acc ++ [message]

        if message["id"] == message_id do
          {:halt, {next, true}}
        else
          {:cont, {next, false}}
        end
      end)

    Enum.filter(items, &(&1["role"] in ["user", "assistant"]))
  end

  defp update_message(messages, message_id, fun) do
    Enum.map(messages, fn
      %{"id" => ^message_id} = message -> fun.(message)
      message -> message
    end)
  end

  defp insert_after_message(messages, message_id, message_to_insert) do
    {acc, inserted?} =
      Enum.reduce(messages, {[], false}, fn message, {items, inserted?} ->
        items = items ++ [message]

        if not inserted? and message["id"] == message_id do
          {items ++ [message_to_insert], true}
        else
          {items, inserted?}
        end
      end)

    if inserted?, do: acc, else: acc ++ [message_to_insert]
  end

  defp latest_assistant_index(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {%{"role" => "assistant"}, index} -> index
      _ -> nil
    end)
  end

  defp latest_streaming_assistant_index(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {%{"role" => "assistant", "content" => ""}, index} -> index
      _ -> nil
    end)
  end

  defp mark_message_status(messages, message_id, status) do
    update_message(messages, message_id, &Map.put(&1, "delivery_status", status))
  end

  defp mark_latest_user_message_complete(messages) do
    case Enum.find_index(
           Enum.reverse(messages),
           &(&1["role"] == "user" and &1["delivery_status"] == "sending")
         ) do
      nil ->
        messages

      reverse_index ->
        index = length(messages) - reverse_index - 1

        List.update_at(messages, index, fn message ->
          Map.put(message, "delivery_status", "sent")
        end)
    end
  end

  defp persist_session_selection(socket) do
    Task.Supervisor.async_nolink(FoundryWeb.ChatTaskSupervisor, fn ->
      DomainLogic.save_session_state(
        socket.assigns.session_id,
        socket.assigns.messages,
        socket.assigns.session_digest,
        socket.assigns.workspace_id,
        socket.assigns.project_fingerprint,
        socket.assigns.selected_model
      )
    end)

    socket
  end
end
