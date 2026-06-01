defmodule FoundryWeb.ChatConfig do
  @moduledoc """
  Centralized configuration for chat system.
  Reads from Application env instead of hardcoding paths or duplicating config.
  """

  require Logger

  # Expected arity for each hook key. Used by validate_hooks!/0 at startup.
  @hook_specs %{
    load_session: 1,
    save_messages: 3,
    rename_session: 2,
    persist_session_memory: 4,
    call_llm_stream: 3,
    build_run_context: 2,
    build_system_prompt: 2
  }

  @doc """
  Validates all configured hooks at application startup.
  Logs a warning for each hook that is configured but has the wrong arity.
  Call this from Application.start/2 or a startup check.
  """
  def validate_hooks! do
    hooks =
      Application.get_env(:foundry_web, :chat_live_hooks) ||
        Application.get_env(:foundry_web, :hooks, %{})

    Enum.each(@hook_specs, fn {key, expected_arity} ->
      value =
        cond do
          is_map(hooks) -> Map.get(hooks, key)
          Keyword.keyword?(hooks) -> Keyword.get(hooks, key)
          true -> nil
        end

      case value do
        nil ->
          :ok

        fun when is_function(fun) ->
          actual = Function.info(fun)[:arity]

          if actual != expected_arity do
            Logger.warning(
              "ChatConfig hook :#{key} has arity #{actual}, expected #{expected_arity}. " <>
                "This hook will be ignored at runtime."
            )
          end

        other ->
          Logger.warning(
            "ChatConfig hook :#{key} is not a function (got #{inspect(other)}). " <>
              "This hook will be ignored at runtime."
          )
      end
    end)
  end

  def project_root do
    Application.get_env(
      :foundry_web,
      :current_project_root,
      Application.get_env(
        :foundry_web,
        :igaming_project_root,
        Application.get_env(:foundry_web, :default_project_root)
      )
    )
  end

  def igaming_project_root, do: project_root()

  def llm_provider do
    Application.get_env(:foundry_web, :llm_provider, :codex)
  end

  def lm_studio_model do
    Application.get_env(:foundry_web, :lm_studio_model, "neural-chat")
  end

  def codex_config do
    Application.get_env(:foundry, :codex, [])
  end

  def claude_code_config do
    Application.get_env(:foundry, :claude_code, [])
  end

  def lm_studio_config do
    Application.get_env(:foundry, :lm_studio, [])
  end

  def gemini_config do
    Application.get_env(:foundry, :gemini, [])
  end

  def hook(key) do
    hooks =
      Application.get_env(:foundry_web, :chat_live_hooks) ||
        Application.get_env(:foundry_web, :hooks, %{})

    cond do
      is_map(hooks) -> Map.get(hooks, key)
      Keyword.keyword?(hooks) -> Keyword.get(hooks, key)
      true -> nil
    end
  end

  def show_debug_details? do
    Application.get_env(:foundry_web, :show_debug_details, false)
  end
end
