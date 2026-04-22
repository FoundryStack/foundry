defmodule Foundry.SparkMeta.SideEffects do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis
  alias Foundry.SparkMeta.{Helpers, SideEffectEntry}

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    classifier = Map.get(analysis.facts, :foundry_classifier, %{})
    reactor = Map.get(analysis.facts, :foundry_reactor, %{steps: []})

    side_effects =
      cond do
        classifier[:type] == :resource ->
          extract_action_side_effects(context.module)

        classifier[:type] in [:reactor, :transfer] ->
          reactor.steps |> Enum.flat_map(& &1.side_effects) |> Enum.uniq()

        classifier[:type] == :trigger ->
          context
          |> Foundry.SparkMeta.ReactorFacts.module_source_context()
          |> then(&extract_module_side_effects(&1.module_source, classifier[:trigger_kind]))

        true ->
          []
      end

    {:ok, Analysis.put_fact(analysis, :foundry_side_effects, side_effects)}
  end

  def extract_side_effects_from_step(nil, _step_name), do: []

  def extract_side_effects_from_step(snippet, step_name) do
    annotated =
      Regex.scan(~r/#\s*@side_effect\s+([^:\n]+):\s*([^,\n]+)(.*)/, snippet)
      |> Enum.map(fn [_, type_str, name_str, rest] ->
        opts = parse_side_effect_opts(rest)

        %SideEffectEntry{
          type: String.trim(type_str) |> String.to_atom(),
          name: String.trim(name_str),
          declared_on: :step,
          step_name: to_string(step_name),
          queue: Map.get(opts, "queue"),
          idempotent: Map.get(opts, "idempotent") == "true",
          idempotency_key_from: Map.get(opts, "key_from") |> parse_list(),
          declared: true,
          epistemic: "VERIFIED"
        }
      end)

    inferred = []

    inferred =
      if String.contains?(snippet, ["Oban.insert", "Oban.insert!"]) and not has_side_effect_type?(annotated, :oban_emit) do
        oban_job_name =
          case Regex.run(~r/Oban\.insert[!]?\(\s*([A-Z][A-Za-z0-9.]+)\.new/, snippet) do
            [_, module] -> module
            _ -> "unnamed_oban_job"
          end

        inferred ++
          [
            %SideEffectEntry{
              type: :oban_emit,
              name: oban_job_name,
              declared_on: :step,
              step_name: to_string(step_name),
              declared: false,
              epistemic: "INFERRED"
            }
          ]
      else
        inferred
      end

    inferred =
      if String.contains?(snippet, ["Req.", "Finch.", "HTTPoison", "Tesla"]) and
           not has_side_effect_type?(annotated, :external_http) do
        inferred ++
          [
            %SideEffectEntry{
              type: :external_http,
              name: "external_call",
              declared_on: :step,
              step_name: to_string(step_name),
              declared: false,
              epistemic: "INFERRED"
            }
          ]
      else
        inferred
      end

    annotated ++ inferred
  end

  defp extract_action_side_effects(module) do
    try do
      Ash.Resource.Info.actions(module)
      |> Enum.flat_map(fn action ->
        notifiers = Map.get(action, :notifiers, [])
        changes = Map.get(action, :changes, [])

        notifier_entries =
          Enum.map(notifiers, fn notifier ->
            %SideEffectEntry{
              type: :ash_notifier,
              name: Helpers.format_module_fqn(notifier),
              declared_on: :resource_action,
              action: to_string(action.name),
              declared: true,
              epistemic: "VERIFIED"
            }
          end)

        change_entries =
          changes
          |> Enum.filter(fn
            %{change: {change_mod, _opts}} -> trigger_change?(change_mod)
            %{change: change_mod} -> trigger_change?(change_mod)
            _ -> false
          end)
          |> Enum.map(fn
            %{change: {change_mod, _opts}} -> change_mod
            %{change: change_mod} -> change_mod
          end)
          |> Enum.map(fn change_mod ->
            %SideEffectEntry{
              type: :ash_change,
              name: Helpers.format_module_fqn(change_mod),
              declared_on: :resource_action,
              action: to_string(action.name),
              declared: true,
              epistemic: "VERIFIED"
            }
          end)

        notifier_entries ++ change_entries
      end)
    rescue
      _ -> []
    end
  end

  defp trigger_change?(module) do
    module |> to_string() |> String.contains?([".Changes.", ".Notifiers."])
  end

  defp has_side_effect_type?(entries, type), do: Enum.any?(entries, &(&1.type == type))

  defp extract_module_side_effects(nil, _trigger_kind), do: []

  defp extract_module_side_effects(module_source, trigger_kind) do
    Regex.scan(~r/#\s*@side_effect\s+([^:\n]+):\s*([^,\n]+)(.*)/, module_source)
    |> Enum.map(fn [_, type_str, name_str, rest] ->
      opts = parse_side_effect_opts(rest)

      %SideEffectEntry{
        type: String.trim(type_str) |> String.to_atom(),
        name: String.trim(name_str),
        declared_on: :module,
        trigger: trigger_kind && to_string(trigger_kind),
        queue: Map.get(opts, "queue"),
        idempotent: Map.get(opts, "idempotent") == "true",
        idempotency_key_from: Map.get(opts, "key_from") |> parse_list(),
        declared: true,
        epistemic: "VERIFIED"
      }
    end)
  end

  defp parse_side_effect_opts(rest) do
    Regex.scan(~r/,\s*([^:\s]+):\s*([^,\s]+)/, rest)
    |> Enum.into(%{}, fn [_, key, value] -> {key, value} end)
  end

  defp parse_list(nil), do: []

  defp parse_list(str) do
    str
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.trim_leading(&1, ":"))
    |> Enum.reject(&(&1 == ""))
  end
end
