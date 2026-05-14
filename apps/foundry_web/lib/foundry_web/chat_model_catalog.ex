defmodule FoundryWeb.ChatModelCatalog do
  @moduledoc """
  Builds the Studio chat model catalog across local and API-backed families.
  """

  alias Foundry.LMStudioProvider
  alias FoundryWeb.ChatConfig

  @codex_models [
    "gpt-5.5",
    "gpt-5.4",
    "gpt-5.4-mini",
    "gpt-5.3-codex",
    "gpt-5.2"
  ]

  @claude_models [
    "claude-sonnet-4-6",
    "claude-opus-4-7",
    "claude-haiku-4-5"
  ]

  @anthropic_models @claude_models

  def catalog do
    codex_entries() ++ claude_code_entries() ++ anthropic_entries() ++ lm_studio_entries()
  end

  def default_model_id(catalog \\ catalog()) do
    preferred_provider = ChatConfig.llm_provider()
    preferred_model = configured_model_for_provider(preferred_provider)

    cond do
      is_binary(preferred_model) and
          find(catalog, provider: preferred_provider, model_id: preferred_model) ->
        "#{preferred_provider}:#{preferred_model}"

      match =
          Enum.find(
            catalog,
            &(&1.provider == preferred_provider and &1.availability == :available)
          ) ->
        match.id

      match = Enum.find(catalog, &(&1.availability == :available)) ->
        match.id

      match = List.first(catalog) ->
        match.id

      true ->
        nil
    end
  end

  def get(catalog, id) when is_binary(id), do: Enum.find(catalog, &(&1.id == id))
  def get(_catalog, _id), do: nil

  def available?(entry), do: entry && entry.availability == :available

  def family_groups(catalog) do
    catalog
    |> Enum.group_by(& &1.family_label)
    |> Enum.sort_by(fn {family_label, _entries} -> family_sort_key(family_label) end)
  end

  def pretty_provider_label(:claude_code), do: "Claude Code"
  def pretty_provider_label(:codex), do: "Codex"
  def pretty_provider_label(:lm_studio), do: "LM Studio"
  def pretty_provider_label(:anthropic), do: "Anthropic"
  def pretty_provider_label(provider), do: provider |> to_string() |> String.replace("_", " ")

  defp codex_entries do
    Enum.map(@codex_models, fn model_id ->
      build_entry(:codex, "Codex (Local)", model_id, available: true, context_window: 400_000)
    end)
  end

  defp claude_code_entries do
    Enum.map(@claude_models, fn model_id ->
      build_entry(:claude_code, "Claude Code (Local)", model_id,
        available: true,
        context_window: 200_000
      )
    end)
  end

  defp anthropic_entries do
    Enum.map(@anthropic_models, fn model_id ->
      build_entry(:anthropic, "Anthropic (API)", model_id,
        available: false,
        disabled_reason: "Anthropic API backend not implemented",
        context_window: 200_000
      )
    end)
  end

  defp lm_studio_entries do
    case discover_lm_studio_models() do
      {:ok, []} ->
        [
          build_entry(:lm_studio, "LM Studio", "unavailable",
            available: false,
            disabled_reason: "No LM Studio models available"
          )
        ]

      {:ok, models} ->
        Enum.map(models, fn model_id ->
          build_entry(:lm_studio, "LM Studio", model_id, available: true)
        end)

      {:error, _reason} ->
        [
          build_entry(:lm_studio, "LM Studio", "unavailable",
            available: false,
            disabled_reason: "LM Studio unavailable"
          )
        ]
    end
  end

  defp discover_lm_studio_models do
    case Application.get_env(:foundry_web, :chat_model_catalog_lm_studio) do
      fun when is_function(fun, 0) ->
        fun.()

      _ ->
        config = ChatConfig.lm_studio_config()
        base_url = Keyword.get(config, :base_url, "http://localhost:1234/v1")
        LMStudioProvider.list_models(base_url: base_url)
    end
  end

  defp build_entry(provider, family_label, model_id, opts) do
    availability =
      if Keyword.get(opts, :available, true), do: :available, else: :disabled

    %{
      id: "#{provider}:#{model_id}",
      provider: provider,
      family_label: family_label,
      model_id: model_id,
      label: pretty_model_label(provider, model_id),
      availability: availability,
      disabled_reason: Keyword.get(opts, :disabled_reason),
      context_window: Keyword.get(opts, :context_window)
    }
  end

  defp pretty_model_label(:codex, model_id), do: "Codex #{upcase_gpt_series(model_id)}"
  defp pretty_model_label(:claude_code, model_id), do: pretty_model_name(model_id)
  defp pretty_model_label(:anthropic, model_id), do: "Anthropic #{pretty_model_name(model_id)}"
  defp pretty_model_label(:lm_studio, model_id), do: pretty_model_name(model_id)
  defp pretty_model_label(_provider, model_id), do: pretty_model_name(model_id)

  defp upcase_gpt_series(model_id) do
    model_id
    |> String.replace("gpt-", "GPT ")
    |> String.replace("-mini", " Mini")
    |> String.replace("-codex", " Codex")
  end

  defp pretty_model_name(model_id) do
    model_id
    |> String.split("/")
    |> case do
      [vendor, name] -> "#{vendor} #{name}"
      parts -> Enum.join(parts, " ")
    end
    |> String.replace(~r/[-_]/, " ")
    |> String.replace(~r/\b([a-z])/, &String.upcase(&1))
    |> String.replace(~r/\b(\d+)b\b/i, "\\1B")
    |> String.replace(~r/\bAi\b/, "AI")
    |> String.replace(~r/\bGpt\b/, "GPT")
  end

  defp configured_model_for_provider(:claude_code),
    do: Keyword.get(ChatConfig.claude_code_config(), :model)

  defp configured_model_for_provider(:codex),
    do: Keyword.get(ChatConfig.codex_config(), :model)

  defp configured_model_for_provider(:lm_studio),
    do: Keyword.get(ChatConfig.lm_studio_config(), :model)

  defp configured_model_for_provider(_provider), do: nil

  defp find(catalog, provider: provider, model_id: model_id) do
    Enum.find(catalog, &(&1.provider == provider and &1.model_id == model_id))
  end

  defp family_sort_key("Codex (Local)"), do: 0
  defp family_sort_key("Claude Code (Local)"), do: 1
  defp family_sort_key("Anthropic (API)"), do: 2
  defp family_sort_key("LM Studio"), do: 3
  defp family_sort_key(_family), do: 99
end
