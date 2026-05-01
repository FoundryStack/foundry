defmodule FoundryWeb.ChatLive do
  use FoundryWeb, :live_view
  require Ash.Query

  @moduledoc """
  Minimal chat LiveView for validating the MCP tool-call flow.

  Sessions are persisted in Mnesia (disc_copies) so they survive server restarts.
  """

  @impl true
  def mount(_params, session, socket) do
    session_id = Map.get(session, "chat_session_id", Ecto.UUID.generate())

    messages =
      case load_session(session_id) do
        {:ok, %Foundry.Chat.Session{} = chat_session} -> chat_session.messages
        _ -> []
      end

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:messages, messages)
      |> assign(:input, "")
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> assign(:active_request_ref, nil)
      |> assign(:project_root, project_root())
      |> assign(:show_system_context, false)
      |> assign(:system_context_prompt, nil)
      |> assign(:system_context_error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_system_context", _params, socket) do
    if socket.assigns.show_system_context do
      {:noreply, assign(socket, :show_system_context, false)}
    else
      {:noreply, load_system_context(socket)}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      user_msg = %{
        "role" => "user",
        "content" => message,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      request_ref = make_ref()
      persisted_messages = socket.assigns.messages ++ [user_msg]

      assistant_msg = %{
        "role" => "assistant",
        "content" => "",
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      messages = persisted_messages ++ [assistant_msg]
      save_messages(socket.assigns.session_id, persisted_messages)

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:input, "")
        |> assign(:loading, true)
        |> assign(:error, nil)
        |> assign(:active_request_ref, request_ref)

      start_llm_stream(request_ref, persisted_messages, self())

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:llm_stream_delta, request_ref, delta}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      {:noreply, update(socket, :messages, &append_to_streaming_response(&1, delta))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_done, request_ref, response}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      messages = finalize_streaming_response(socket.assigns.messages, response)
      save_messages(socket.assigns.session_id, messages)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:loading, false)
       |> assign(:active_request_ref, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_error, request_ref, reason}, socket) do
    if request_ref == socket.assigns.active_request_ref do
      messages = drop_empty_streaming_response(socket.assigns.messages)
      save_messages(socket.assigns.session_id, messages)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:loading, false)
       |> assign(:active_request_ref, nil)
       |> assign(:error, "Failed to get response: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  defp start_llm_stream(request_ref, messages, live_view_pid) do
    spawn(fn ->
      case call_llm_stream(messages, fn event ->
             send(live_view_pid, format_stream_event(request_ref, event))
           end) do
        {:ok, response} ->
          send(live_view_pid, {:llm_stream_done, request_ref, response})

        {:error, reason} ->
          send(live_view_pid, {:llm_stream_error, request_ref, reason})
      end
    end)
  end

  defp format_stream_event(request_ref, {:delta, text}),
    do: {:llm_stream_delta, request_ref, text}

  defp append_to_streaming_response(messages, delta) do
    update_last_message(messages, fn msg ->
      Map.update(msg, "content", delta, &(&1 <> delta))
    end)
  end

  defp finalize_streaming_response(messages, ""), do: messages

  defp finalize_streaming_response(messages, response) do
    update_last_message(messages, &Map.put(&1, "content", response))
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
    Foundry.Chat.Session
    |> Ash.Query.filter(session_id: session_id)
    |> Ash.read_one(domain: Foundry.Chat)
  end

  defp save_messages(session_id, messages) do
    case load_session(session_id) do
      {:ok, nil} ->
        Foundry.Chat.Session
        |> Ash.Changeset.for_create(:create, %{session_id: session_id, messages: messages},
          domain: Foundry.Chat
        )
        |> Ash.create()

      {:ok, %Foundry.Chat.Session{} = existing} ->
        existing
        |> Ash.Changeset.for_update(:update, %{messages: messages}, domain: Foundry.Chat)
        |> Ash.update()

      _ ->
        :ok
    end
  end

  defp call_llm(messages) do
    provider = Application.get_env(:foundry, :llm_provider, :claude_code)

    case provider do
      :claude_code ->
        call_claude_code(messages)

      :lm_studio ->
        call_lm_studio(messages)

      :codex ->
        call_codex(messages)

      :req_llm ->
        call_req_llm(messages)

      _ ->
        {:error, {:unknown_provider, provider}}
    end
  end

  defp call_llm_stream(messages, on_event) do
    provider = Application.get_env(:foundry, :llm_provider, :claude_code)

    case provider do
      :claude_code ->
        call_claude_code_stream(messages, on_event)

      :lm_studio ->
        call_lm_studio_stream(messages, on_event)

      :codex ->
        call_codex_stream(messages, on_event)

      _ ->
        call_llm(messages)
    end
  end

  # ---------------------------------------------------------------------------
  # Claude Code CLI provider (default for dev — no API key needed)
  # ---------------------------------------------------------------------------

  defp call_claude_code(messages) do
    call_claude_code_stream(messages, fn _event -> :ok end)
  end

  defp call_claude_code_stream(messages, on_event) do
    project_root = project_root()

    with {:ok, system_prompt} <- build_system_prompt(project_root) do
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
        {:ok, text, _metadata} ->
          {:ok, text}

        {:error, :not_installed} ->
          {:ok, claude_not_installed_message()}

        {:error, {:timeout, partial_text}} ->
          if String.length(partial_text) > 0 do
            {:ok, partial_text <> "\n\n[Response timed out — partial response above]"}
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

  defp build_system_prompt(project_root) do
    system_prompt =
      Foundry.Copilot.ContextBuilder.build(
        project_root: Application.fetch_env!(:foundry_web, :igaming_project_root)
      )

    {:ok, target_project_header(project_root) <> system_prompt}
  rescue
    e -> {:error, {:context_build_failed, Exception.message(e)}}
  catch
    :exit, reason -> {:error, {:context_build_failed, reason}}
    kind, reason -> {:error, {:context_build_failed, {kind, reason}}}
  end

  defp project_root do
    :foundry_web
    |> Application.fetch_env!(:igaming_project_root)
    |> Path.expand()
  end

  defp target_project_header(project_root) do
    """
    # Target Project Boundary

    The target platform for this chat is the reference iGaming project.
    Target project root: #{project_root}

    Treat this directory as the authoritative workspace for project discovery,
    code inspection, and Mix commands. Do not inspect or modify the parent
    Foundry repository unless the user explicitly asks about Foundry itself.

    ---

    """
  end

  defp load_system_context(socket) do
    project_root = socket.assigns.project_root

    case build_system_prompt(project_root) do
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

  # ---------------------------------------------------------------------------
  # OpenAI Codex CLI provider
  # ---------------------------------------------------------------------------

  defp call_codex(messages) do
    call_codex_stream(messages, fn _event -> :ok end)
  end

  defp call_codex_stream(messages, on_event) do
    project_root = project_root()

    with {:ok, system_prompt} <- build_system_prompt(project_root) do
      config = Application.get_env(:foundry, :codex, [])

      opts = [
        system_prompt: system_prompt,
        timeout_ms: Keyword.get(config, :timeout_ms, 120_000),
        model: Keyword.get(config, :model),
        profile: Keyword.get(config, :profile),
        sandbox: Keyword.get(config, :sandbox, "read-only"),
        executable: Keyword.get(config, :executable, "codex"),
        project_root: project_root
      ]

      case Foundry.CodexProvider.stream(messages, opts, fn
             {:delta, text} -> on_event.({:delta, text})
             _event -> :ok
           end) do
        {:ok, text, _metadata} ->
          {:ok, text}

        {:error, :not_installed} ->
          {:ok, codex_not_installed_message()}

        {:error, {:timeout, partial_text}} ->
          if String.length(partial_text) > 0 do
            {:ok, partial_text <> "\n\n[Response timed out — partial response above]"}
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

  # ---------------------------------------------------------------------------
  # LM Studio local OpenAI-compatible provider
  # ---------------------------------------------------------------------------

  defp call_lm_studio(messages) do
    call_lm_studio_stream(messages, fn _event -> :ok end)
  end

  defp call_lm_studio_stream(messages, on_event) do
    project_root = project_root()

    with {:ok, system_prompt} <- build_system_prompt(project_root) do
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
        {:ok, text, _metadata} ->
          {:ok, text}

        {:error, {:timeout, partial_text}} ->
          if String.length(partial_text) > 0 do
            {:ok, partial_text <> "\n\n[Response timed out — partial response above]"}
          else
            {:error, :timeout}
          end

        {:error, reason} ->
          {:error, {:lm_studio_error, reason}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # req_llm + AshAi.ToolLoop provider (production path — needs API key)
  # ---------------------------------------------------------------------------

  defp call_req_llm(messages) do
    prompt =
      messages
      |> Enum.map(fn %{"content" => c, "role" => r} -> "#{r}: #{c}" end)
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
    messages = [
      %{role: "user", content: prompt}
    ]

    case AshAi.ToolLoop.run(messages,
           model: model,
           otp_app: :foundry
         ) do
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

  # Render
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-4 h-screen flex flex-col">
      <div class="mb-4 flex items-start justify-between gap-3">
        <div>
          <h1 class="text-xl font-bold">Foundry Chat</h1>
          <p class="text-xs text-gray-500 break-all">{@project_root}</p>
        </div>

        <button
          type="button"
          phx-click="toggle_system_context"
          class="shrink-0 border border-gray-300 text-gray-700 px-3 py-2 rounded-lg text-sm hover:bg-gray-50"
        >
          {if @show_system_context, do: "Hide context", else: "Show context"}
        </button>
      </div>

      <%= if @show_system_context do %>
        <div class="mb-4 border border-gray-200 rounded-lg bg-gray-50 p-3">
          <div class="flex items-center justify-between gap-3 mb-2">
            <p class="text-sm font-semibold text-gray-700">System Context Prompt</p>
            <%= if @system_context_prompt do %>
              <p class="text-xs text-gray-500">{byte_size(@system_context_prompt)} bytes</p>
            <% end %>
          </div>

          <%= if @system_context_error do %>
            <p class="text-sm text-red-600 whitespace-pre-wrap">{@system_context_error}</p>
          <% else %>
            <pre class="max-h-64 overflow-auto text-xs leading-5 whitespace-pre-wrap text-gray-800"><%= @system_context_prompt %></pre>
          <% end %>
        </div>
      <% end %>

      <div class="flex-1 overflow-y-auto mb-4 space-y-3">
        <%= for msg <- @messages do %>
          <div class={[
            "rounded-lg p-3 max-w-[80%]",
            if(msg["role"] == "user", do: "bg-blue-100 ml-auto", else: "bg-gray-100")
          ]}>
            <p class="text-sm font-semibold mb-1">
              {if msg["role"] == "user", do: "You", else: "Assistant"}
            </p>
            <p class="whitespace-pre-wrap">{msg["content"]}</p>
          </div>
        <% end %>

        <%= if @loading do %>
          <div class="bg-gray-50 rounded-lg p-3 max-w-[80%]">
            <p class="text-sm text-gray-500">Thinking...</p>
          </div>
        <% end %>
      </div>

      <%= if @error do %>
        <div class="bg-red-50 text-red-600 rounded p-2 mb-2 text-sm">
          {@error}
        </div>
      <% end %>

      <form phx-submit="send_message" class="flex gap-2">
        <input
          type="text"
          name="message"
          value={@input}
          placeholder="Type a message..."
          class="flex-1 border rounded-lg px-3 py-2"
          disabled={@loading}
        />
        <button
          type="submit"
          disabled={@loading}
          class="bg-blue-600 text-white px-4 py-2 rounded-lg disabled:opacity-50"
        >
          Send
        </button>
      </form>
    </div>
    """
  end
end
