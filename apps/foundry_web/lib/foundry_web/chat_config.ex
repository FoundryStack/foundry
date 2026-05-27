defmodule FoundryWeb.ChatConfig do
  @moduledoc """
  Centralized configuration for chat system.
  Reads from Application env instead of hardcoding paths or duplicating config.
  """

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
