defmodule PhoenixLLMChat.LLMContext do
  @moduledoc """
  LLM provider abstraction and streaming orchestration.

  Supports multiple providers (Claude, Codex, LM Studio, HTTP) with:
  - Provider detection and routing
  - System prompt building with hooks
  - Streaming request setup
  - Provider config and diagnostics
  """

  import Phoenix.Component, only: [assign: 3]
  require Logger

  def call_llm(socket, user_message, options \\ []) do
    provider = get_provider(socket)
    system_prompt = build_system_prompt(socket, options)

    messages = [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => user_message}
    ]

    case call_llm_stream(socket, provider, messages, options) do
      {:ok, request_ref} ->
        {:ok, assign(socket, :current_request_ref, request_ref)}

      {:error, reason} ->
        Logger.error("Failed to call LLM: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def call_llm_stream(socket, provider, messages, options \\ []) do
    case provider do
      "claude" -> call_claude_stream(socket, messages, options)
      "codex" -> call_codex_stream(socket, messages, options)
      "lm_studio" -> call_lm_studio_stream(socket, messages, options)
      "http" -> call_http_stream(socket, messages, options)
      _ -> {:error, {:unknown_provider, provider}}
    end
  rescue
    e ->
      Logger.error("Stream error: #{inspect(e)}")
      {:error, e}
  end

  def build_system_prompt(socket, options \\ []) do
    base_prompt = "You are a helpful assistant."

    case apply_hook(:build_system_prompt, [socket, options]) do
      {:ok, custom_prompt} -> custom_prompt
      :not_configured -> base_prompt
    end
  end

  def get_provider(socket) do
    apply_hook(:get_provider, [socket]) || Application.get_env(:phoenix_llm_chat, :default_provider, "claude")
  end

  def get_provider_config(provider_name) do
    case apply_hook(:get_provider_config, [provider_name]) do
      {:ok, config} -> config
      :not_configured -> default_config(provider_name)
    end
  end

  def llm_diagnostics(socket) do
    %{
      provider: get_provider(socket),
      hooks_configured: configured_hooks(),
      timestamp: DateTime.utc_now()
    }
  end

  defp call_claude_stream(socket, messages, options) do
    # Hook point for custom Claude implementation
    case apply_hook(:call_llm_stream, [:claude, socket, messages, options]) do
      {:ok, request_ref} -> {:ok, request_ref}
      :not_configured -> {:error, :claude_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_codex_stream(socket, messages, options) do
    # Hook point for custom Codex implementation
    case apply_hook(:call_llm_stream, [:codex, socket, messages, options]) do
      {:ok, request_ref} -> {:ok, request_ref}
      :not_configured -> {:error, :codex_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_lm_studio_stream(socket, messages, options) do
    # Hook point for custom LM Studio implementation
    case apply_hook(:call_llm_stream, [:lm_studio, socket, messages, options]) do
      {:ok, request_ref} -> {:ok, request_ref}
      :not_configured -> {:error, :lm_studio_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_http_stream(_socket, _messages, options) do
    # Generic HTTP provider with Req (stub for hook override)
    url = options[:url] || Application.get_env(:phoenix_llm_chat, :llm_endpoint)

    case url do
      nil ->
        {:error, :no_http_endpoint}

      _endpoint ->
        try do
          {:ok, make_ref()}
        rescue
          e -> {:error, e}
        end
    end
  end

  defp apply_hook(hook_name, args) do
    case Application.get_env(:phoenix_llm_chat, :hooks, %{})[hook_name] do
      nil -> :not_configured
      hook_fn -> apply(hook_fn, args)
    end
  end

  defp configured_hooks do
    Application.get_env(:phoenix_llm_chat, :hooks, %{})
    |> Map.keys()
  end

  defp default_config(provider_name) do
    %{
      provider: provider_name,
      base_url: nil,
      model: nil,
      api_key: nil
    }
  end
end
