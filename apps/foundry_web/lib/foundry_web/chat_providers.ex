defmodule FoundryWeb.ChatProviders do
  @moduledoc """
  Provider selection and dispatch for LLM streaming.
  Routes requests to the appropriate provider based on configuration.
  """

  require Logger
  alias FoundryWeb.ChatConfig

  def call_stream(messages, on_event, run_context) do
    case ChatConfig.hook(:call_llm_stream) do
      nil -> dispatch_by_provider(messages, on_event, run_context)
      fun -> call_hooked_provider(fun, messages, on_event, run_context)
    end
  end

  defp dispatch_by_provider(messages, on_event, run_context) do
    case ChatConfig.llm_provider() do
      :claude_code -> call_claude_code(messages, on_event, run_context)
      :codex -> call_codex(messages, on_event, run_context)
      :lm_studio -> call_lm_studio(messages, on_event, run_context)
      _ -> {:error, {:unknown_provider, ChatConfig.llm_provider()}}
    end
  end

  defp call_hooked_provider(fun, messages, on_event, run_context) do
    case :erlang.fun_info(fun, :arity) do
      {:arity, 3} -> fun.(messages, on_event, run_context)
      _ -> fun.(messages, on_event)
    end
  end

  defp call_claude_code(messages, on_event, run_context) do
    request_ref = make_ref()
    liveview_pid = self()

    Task.start_link(fn ->
      opts = [
        system_prompt: run_context.system_prompt,
        timeout_ms: Keyword.get(ChatConfig.claude_code_config(), :timeout_ms, 120_000),
        model: Keyword.get(ChatConfig.claude_code_config(), :model),
        project_root: ChatConfig.igaming_project_root()
      ]

      case Foundry.ClaudeCodeProvider.stream(messages, opts, fn
             {:delta, text} -> on_event.({:delta, text})
             _event -> :ok
           end) do
        {:ok, _text, metadata} ->
          send(liveview_pid, {:llm_stream_done, request_ref, "", metadata})

        {:error, :not_installed} ->
          send(liveview_pid, {:llm_stream_error, request_ref, :claude_code_not_installed})

        {:error, {:timeout, _partial_text, _metadata}} ->
          send(liveview_pid, {:llm_stream_error, request_ref, :timeout})

        {:error, reason} ->
          send(liveview_pid, {:llm_stream_error, request_ref, reason})
      end
    end)

    {:ok, request_ref}
  rescue
    _ -> {:error, {:claude_code_error, "Claude Code not available"}}
  end

  defp call_codex(messages, on_event, run_context) do
    request_ref = make_ref()
    liveview_pid = self()

    Task.start_link(fn ->
      config = ChatConfig.codex_config()

      opts = [
        system_prompt: run_context.system_prompt,
        timeout_ms: Keyword.get(config, :timeout_ms, 120_000),
        model: Keyword.get(config, :model),
        profile: Keyword.get(config, :profile),
        sandbox: Keyword.get(config, :sandbox, "workspace-write"),
        executable: Keyword.get(config, :executable, "codex"),
        project_root: ChatConfig.igaming_project_root(),
        conversation_window: :all
      ]

      case Foundry.CodexProvider.stream(messages, opts, fn
             {:delta, text} -> on_event.({:delta, text})
             {:trace, event} -> on_event.({:trace, event})
             _event -> :ok
           end) do
        {:ok, _text, metadata} ->
          send(liveview_pid, {:llm_stream_done, request_ref, "", metadata})

        {:error, :not_installed} ->
          send(liveview_pid, {:llm_stream_error, request_ref, :codex_not_installed})

        {:error, {:timeout, _partial_text, _metadata}} ->
          send(liveview_pid, {:llm_stream_error, request_ref, :timeout})

        {:error, reason} ->
          send(liveview_pid, {:llm_stream_error, request_ref, reason})
      end
    end)

    {:ok, request_ref}
  rescue
    _ -> {:error, {:codex_error, "Codex not available"}}
  end

  defp call_lm_studio(messages, on_event, run_context) do
    request_ref = make_ref()
    liveview_pid = self()

    Task.start_link(fn ->
      config = ChatConfig.lm_studio_config()

      opts = [
        system_prompt: run_context.system_prompt,
        endpoint: Keyword.get(config, :endpoint, "http://localhost:1234"),
        model: Keyword.get(config, :model, ChatConfig.lm_studio_model()),
        timeout_ms: Keyword.get(config, :timeout_ms, 120_000)
      ]

      case Foundry.LMStudioProvider.stream(messages, opts, fn
             {:delta, text} -> on_event.({:delta, text})
             _event -> :ok
           end) do
        {:ok, _text, metadata} ->
          send(liveview_pid, {:llm_stream_done, request_ref, "", metadata})

        {:error, :not_installed} ->
          send(liveview_pid, {:llm_stream_error, request_ref, :lm_studio_not_installed})

        {:error, reason} ->
          send(liveview_pid, {:llm_stream_error, request_ref, reason})
      end
    end)

    {:ok, request_ref}
  rescue
    _ -> {:error, {:lm_studio_error, "LM Studio not available"}}
  end
end
