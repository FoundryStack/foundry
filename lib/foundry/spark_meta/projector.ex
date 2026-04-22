defmodule Foundry.SparkMeta.Projector do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis
  alias Foundry.SparkMeta.{Action, Attribute, MoneyAttr, ModuleInfo}

  @impl SparkMeta.Analyzer
  def analyze(_context, %Analysis{} = analysis) do
    {:ok, Analysis.put_fact(analysis, :module_info, to_module_info(analysis))}
  end

  def to_module_info(%Analysis{module: module} = analysis) do
    ash_resource = Map.get(analysis.facts, :ash_resource, %{})
    classifier = Map.get(analysis.facts, :foundry_classifier, %{})
    governance = Map.get(analysis.facts, :foundry_governance, %{})
    reactor = Map.get(analysis.facts, :foundry_reactor, %{steps: []})

    attributes =
      ash_resource
      |> Map.get(:attributes, [])
      |> Enum.filter(&keep_attribute?/1)
      |> Enum.map(&attribute_to_struct/1)

    %ModuleInfo{
      module: module,
      type: classifier[:type],
      description: governance[:description],
      attributes: attributes,
      actions: Enum.map(Map.get(ash_resource, :actions, []), &action_to_struct/1),
      rules: [],
      compliance: governance[:compliance] || Map.get(ash_resource, :compliance, []),
      adrs: governance[:adrs] || [],
      runbook: governance[:runbook],
      data_layer: Map.get(ash_resource, :data_layer) |> format_data_layer(),
      paper_trail: classifier[:paper_trail] || false,
      archival: classifier[:archival] || false,
      state_machine: Map.get(analysis.facts, :state_machine, default_state_machine()),
      api_routes: [],
      telemetry_prefix: governance[:telemetry_prefix] || Map.get(ash_resource, :telemetry_prefix, []),
      money_attributes: money_attributes(attributes),
      authentication_subject: classifier[:authentication_subject] || false,
      oban_queues: classifier[:oban_queues] || [],
      rate_limited: classifier[:rate_limited] || false,
      feature_flags: [],
      steps: reactor[:steps] || [],
      outputs: [],
      agent_steps: [],
      performs: classifier[:performs],
      last_modified: classifier[:last_modified],
      relationships: [],
      auth_strategies: [],
      side_effects: Map.get(analysis.facts, :foundry_side_effects, []),
      trigger_kind: classifier[:trigger_kind],
      diagnostics: analysis.diagnostics
    }
  end

  defp attribute_to_struct(%{name: name, type: type, description: description} = attr) do
    %Attribute{
      name: name,
      type: format_type(type),
      description: description,
      pii: false,
      sensitive: Map.get(attr, :sensitive?, false) || false,
      money: type == Ash.Type.Money,
      cldr_backend: extract_cldr_backend(type, attr)
    }
  rescue
    _ -> %Attribute{name: name, type: "unknown", description: description}
  end

  defp action_to_struct(%{name: name, type: type, description: description}) do
    %Action{name: name, type: type, description: description}
  rescue
    _ -> %Action{name: :unknown, type: :unknown, description: nil}
  end

  defp money_attributes(attributes) do
    attributes
    |> Enum.filter(&(&1.type == "Ash.Type.Money"))
    |> Enum.map(&%MoneyAttr{name: &1.name, type: &1.type, cldr_backend: &1.cldr_backend})
  end

  defp keep_attribute?(attribute) do
    described?(attribute) or
      (
        Map.get(attribute, :public?, true) and
          not Map.get(attribute, :primary_key?, false) and
          Map.get(attribute, :name) not in [:state] and
          not is_nil(Map.get(attribute, :__spark_metadata__))
      )
  end

  defp described?(attribute) do
    description = Map.get(attribute, :description)
    is_binary(description) and description != ""
  end

  defp format_type(type) when is_atom(type), do: to_string(type)
  defp format_type(type) when is_binary(type), do: type
  defp format_type(_type), do: "unknown"

  defp extract_cldr_backend(Ash.Type.Money, attr) do
    attr |> Map.get(:constraints, []) |> Keyword.get(:cldr_backend)
  rescue
    _ -> nil
  end

  defp extract_cldr_backend(_type, _attr), do: nil

  defp format_data_layer(nil), do: nil
  defp format_data_layer(data_layer) when is_atom(data_layer), do: to_string(data_layer)
  defp format_data_layer(data_layer), do: data_layer

  defp default_state_machine do
    %{
      present: false,
      states: [],
      transitions: [],
      state_attribute: nil,
      initial_states: [],
      default_initial_state: nil,
      terminal_states: []
    }
  end
end
