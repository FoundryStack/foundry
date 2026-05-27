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
    case provider_from_run_context(run_context) do
      :claude_code -> call_claude_code(messages, on_event, run_context)
      :codex -> call_codex(messages, on_event, run_context)
      :lm_studio -> call_lm_studio(messages, on_event, run_context)
      :gemini -> call_gemini(messages, on_event, run_context)
      _ -> {:error, {:unknown_provider, provider_from_run_context(run_context)}}
    end
  end

  defp call_hooked_provider(fun, messages, on_event, run_context) do
    case :erlang.fun_info(fun, :arity) do
      {:arity, 3} -> fun.(messages, on_event, run_context)
      _ -> fun.(messages, on_event)
    end
  end

  defp call_claude_code(messages, on_event, run_context) do
    opts = [
      system_prompt: run_context.system_prompt,
      timeout_ms: Keyword.get(ChatConfig.claude_code_config(), :timeout_ms, 120_000),
      model:
        model_from_run_context(run_context) ||
          Keyword.get(ChatConfig.claude_code_config(), :model),
      project_root: ChatConfig.project_root()
    ]

    Foundry.ClaudeCodeProvider.stream(messages, opts, fn
      {:delta, text} -> on_event.({:delta, text})
      _event -> :ok
    end)
  rescue
    _ -> {:error, {:claude_code_error, "Claude Code not available"}}
  end

  defp call_codex(messages, on_event, run_context) do
    config = ChatConfig.codex_config()

    opts = [
      system_prompt: run_context.system_prompt,
      timeout_ms: Keyword.get(config, :timeout_ms, 120_000),
      model: model_from_run_context(run_context) || Keyword.get(config, :model),
      profile: Keyword.get(config, :profile),
      sandbox: Keyword.get(config, :sandbox, "workspace-write"),
      executable: Keyword.get(config, :executable, "codex"),
      project_root: ChatConfig.project_root(),
      conversation_window: :all
    ]

    Foundry.CodexProvider.stream(messages, opts, fn
      {:delta, text} -> on_event.({:delta, text})
      {:trace, event} -> on_event.({:trace, event})
      _event -> :ok
    end)
  rescue
    _ -> {:error, {:codex_error, "Codex not available"}}
  end

  defp call_lm_studio(messages, on_event, run_context) do
    config = ChatConfig.lm_studio_config()

    opts = [
      system_prompt: run_context.system_prompt,
      base_url: Keyword.get(config, :base_url, "http://localhost:1234/v1"),
      model:
        model_from_run_context(run_context) ||
          Keyword.get(config, :model, ChatConfig.lm_studio_model()),
      timeout_ms: Keyword.get(config, :timeout_ms, 120_000)
    ]

    Foundry.LMStudioProvider.stream(messages, opts, fn
      {:delta, text} -> on_event.({:delta, text})
      _event -> :ok
    end)
  rescue
    _ -> {:error, {:lm_studio_error, "LM Studio not available"}}
  end

  defp call_gemini(messages, on_event, run_context) do
    config = ChatConfig.gemini_config()

    opts = [
      system_prompt: run_context.system_prompt,
      api_key: Keyword.get(config, :api_key) || System.get_env("GEMINI_API_KEY"),
      model:
        model_from_run_context(run_context) ||
          Keyword.get(config, :model, "gemini-3.5-flash"),
      timeout_ms: Keyword.get(config, :timeout_ms, 120_000)
    ]

    Foundry.GeminiProvider.stream(messages, opts, fn
      {:delta, text} -> on_event.({:delta, text})
      _event -> :ok
    end)
  rescue
    _ -> {:error, {:gemini_error, "Gemini API not available"}}
  end

  defp provider_from_run_context(%{selected_model: %{provider: provider}}), do: provider
  defp provider_from_run_context(_run_context), do: ChatConfig.llm_provider()

  defp model_from_run_context(%{selected_model: %{model_id: model_id}}), do: model_id
  defp model_from_run_context(_run_context), do: nil
end
