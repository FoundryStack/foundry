defmodule SparkMeta.Analyzers.AuthStrategies do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    strategies =
      if has_auth_extension?(analysis) do
        global_token_resource =
          context.module
          |> SparkMeta.Walker.get_opt([:authentication, :tokens], :token_resource, nil)
          |> format_module()

        context.module
        |> SparkMeta.Walker.entities([:authentication, :strategies])
        |> Enum.map(&map_strategy(&1, global_token_resource))
      else
        []
      end

    {:ok, Analysis.put_fact(analysis, :auth_strategies, strategies)}
  end

  defp has_auth_extension?(analysis) do
    Map.get(analysis.facts, :extensions, [])
    |> Enum.any?(fn extension ->
      extension in [AshAuthentication, AshAuthentication.Resource] or
        String.contains?(to_string(extension), "AshAuthentication")
    end)
  rescue
    _ -> false
  end

  defp map_strategy(strategy, global_token_resource) do
    %{
      strategy_name: to_string(Map.get(strategy, :name, :unknown)),
      strategy_type: strategy_type(strategy),
      identity_field: stringify(Map.get(strategy, :identity_field)),
      token_resource: format_module(Map.get(strategy, :token_resource)) || global_token_resource,
      has_sign_in_tokens:
        Map.get(strategy, :sign_in_tokens_enabled) == true or
          Map.get(strategy, :sign_in_tokens_enabled?) == true,
      has_password_reset:
        Map.get(strategy, :password_reset_enabled) == true or
          Map.get(strategy, :password_reset_enabled?) == true or
          not is_nil(Map.get(strategy, :resettable))
    }
  end

  defp strategy_type(strategy) do
    strategy.__struct__
    |> Module.split()
    |> List.last()
    |> String.downcase()
    |> String.to_atom()
  rescue
    _ -> :other
  end

  defp stringify(nil), do: nil
  defp stringify(value), do: to_string(value)

  defp format_module(nil), do: nil
  defp format_module(module) when is_atom(module), do: module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  defp format_module(module) when is_binary(module), do: module
  defp format_module(_module), do: nil
end
