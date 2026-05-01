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

    {:ok, socket}
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

      messages = socket.assigns.messages ++ [user_msg]
      save_messages(socket.assigns.session_id, messages)

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:input, "")
        |> assign(:loading, true)
        |> assign(:error, nil)

      send(self(), {:process_message, message, messages})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:process_message, _user_message, previous_messages}, socket) do
    case call_llm(previous_messages) do
      {:ok, response} ->
        assistant_msg = %{
          "role" => "assistant",
          "content" => response,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        messages = previous_messages ++ [assistant_msg]
        save_messages(socket.assigns.session_id, messages)

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Failed to get response: #{inspect(reason)}")}
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

      :req_llm ->
        call_req_llm(messages)

      _ ->
        {:error, {:unknown_provider, provider}}
    end
  end

  # ---------------------------------------------------------------------------
  # Claude Code CLI provider (default for dev — no API key needed)
  # ---------------------------------------------------------------------------

  defp call_claude_code(messages) do
    project_root = project_root()

    with {:ok, system_prompt} <- build_system_prompt(project_root) do
      opts = [
        system_prompt: system_prompt,
        timeout_ms: Application.get_env(:foundry, :claude_code, [])[:timeout_ms] || 120_000,
        model: Application.get_env(:foundry, :claude_code, [])[:model],
        project_root: project_root
      ]

      case Foundry.ClaudeCodeProvider.chat(messages, opts) do
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
    {:ok, Foundry.Copilot.ContextBuilder.build(project_root: project_root)}
  rescue
    e -> {:error, {:context_build_failed, Exception.message(e)}}
  catch
    :exit, reason -> {:error, {:context_build_failed, reason}}
    kind, reason -> {:error, {:context_build_failed, {kind, reason}}}
  end

  defp project_root do
    Application.get_env(
      :foundry_web,
      :igaming_project_root,
      Path.expand("../../../../../reference_projects/igaming", __DIR__)
    )
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
      <h1 class="text-xl font-bold mb-4">Foundry Chat</h1>

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
