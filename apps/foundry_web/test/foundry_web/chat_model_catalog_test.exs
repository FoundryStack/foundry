defmodule FoundryWeb.ChatModelCatalogTest do
  use ExUnit.Case, async: true

  alias FoundryWeb.ChatModelCatalog

  setup do
    lm_studio = Application.get_env(:foundry_web, :chat_model_catalog_lm_studio)

    on_exit(fn ->
      restore_env(:foundry_web, :chat_model_catalog_lm_studio, lm_studio)
    end)

    :ok
  end

  test "builds a model-first catalog with discovered LM Studio entries and disabled Anthropic family" do
    Application.put_env(:foundry_web, :chat_model_catalog_lm_studio, fn ->
      {:ok, ["google/gemma-4-31b", "qwen/qwen2.5-coder-32b"]}
    end)

    catalog = ChatModelCatalog.catalog()

    assert Enum.any?(catalog, &(&1.id == "codex:gpt-5.5" and &1.provider == :codex))

    assert Enum.any?(
             catalog,
             &(&1.id == "claude_code:claude-sonnet-4-6" and &1.provider == :claude_code)
           )

    assert Enum.any?(
             catalog,
             &(&1.id == "anthropic:claude-opus-4-7" and &1.availability == :disabled)
           )

    assert Enum.any?(
             catalog,
             &(&1.id == "lm_studio:google/gemma-4-31b" and &1.label == "Google Gemma 4 31B")
           )
  end

  test "falls back to a disabled LM Studio placeholder when discovery fails" do
    Application.put_env(:foundry_web, :chat_model_catalog_lm_studio, fn ->
      {:error, :econnrefused}
    end)

    catalog = ChatModelCatalog.catalog()

    assert Enum.any?(
             catalog,
             &(&1.provider == :lm_studio and &1.availability == :disabled and
                 &1.disabled_reason == "LM Studio unavailable")
           )
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
