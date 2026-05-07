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
    page_meta = Map.get(analysis.facts, :page_metadata, %{})

    state_machine =
      analysis.facts
      |> Map.get(:state_machine, default_state_machine())
      |> resolve_state_machine(module)

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
      state_machine: state_machine,
      api_routes: [],
      telemetry_prefix:
        governance[:telemetry_prefix] || Map.get(ash_resource, :telemetry_prefix, []),
      money_attributes: money_attributes(attributes),
      authentication_subject: classifier[:authentication_subject] || false,
      oban_queues: classifier[:oban_queues] || [],
      rate_limited: classifier[:rate_limited] || false,
      feature_flags: page_meta[:feature_flags] || [],
      steps: reactor[:steps] || [],
      outputs: [],
      agent_steps: [],
      performs: classifier[:performs],
      last_modified: classifier[:last_modified],
      relationships: [],
      auth_strategies: [],
      side_effects: Map.get(analysis.facts, :foundry_side_effects, []),
      trigger_kind: classifier[:trigger_kind],
      diagnostics: analysis.diagnostics,
      page_route: page_meta[:page_route],
      page_group: page_meta[:page_group],
      page_dynamic: page_meta[:page_dynamic] || false,
      page_subtype: page_meta[:page_subtype],
      calls_actions: page_meta[:calls_actions] || []
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
      (Map.get(attribute, :public?, true) and
         not Map.get(attribute, :primary_key?, false) and
         Map.get(attribute, :name) not in [:state] and
         not is_nil(Map.get(attribute, :__spark_metadata__)))
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

  defp resolve_state_machine(state_machine, module) do
    normalized = normalize_state_machine(state_machine)

    if normalized.present do
      normalized
    else
      infer_state_machine_from_dsl(module)
    end
  end

  defp normalize_state_machine(state_machine) when is_map(state_machine) do
    transitions =
      state_machine
      |> Map.get(:transitions, [])
      |> Enum.flat_map(&normalize_transition/1)
      |> Enum.uniq()

    states =
      state_machine
      |> Map.get(:states, [])
      |> normalize_state_list()

    initial_states =
      state_machine
      |> Map.get(:initial_states, [])
      |> normalize_state_list()

    terminal_states =
      state_machine
      |> Map.get(:terminal_states, [])
      |> normalize_state_list()

    default_initial_state =
      state_machine
      |> Map.get(:default_initial_state)
      |> normalize_state_name()

    state_attribute =
      state_machine
      |> Map.get(:state_attribute)
      |> normalize_state_name()

    inferred_states =
      transitions
      |> Enum.flat_map(fn transition ->
        [Map.get(transition, :from), Map.get(transition, :to)]
      end)
      |> Enum.reject(&is_nil/1)

    all_states =
      (states ++ initial_states ++ terminal_states ++ inferred_states ++ [default_initial_state])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    present =
      Map.get(state_machine, :present, false) ||
        all_states != [] ||
        transitions != []

    %{
      present: present,
      states: all_states,
      transitions: transitions,
      state_attribute: state_attribute,
      initial_states: initial_states,
      default_initial_state: default_initial_state,
      terminal_states: terminal_states
    }
  rescue
    _ -> default_state_machine()
  end

  defp normalize_state_machine(_state_machine), do: default_state_machine()

  defp infer_state_machine_from_dsl(module) do
    transitions =
      module
      |> Spark.Dsl.Extension.get_entities([:state_machine, :transitions])
      |> Enum.flat_map(&transition_entity_to_maps/1)
      |> Enum.uniq()

    initial_states =
      module
      |> Spark.Dsl.Extension.get_opt([:state_machine], :initial_states, [])
      |> normalize_state_list()

    default_initial_state =
      module
      |> Spark.Dsl.Extension.get_opt([:state_machine], :default_initial_state, nil)
      |> normalize_state_name()

    terminal_states =
      module
      |> Spark.Dsl.Extension.get_opt([:state_machine], :terminal_states, [])
      |> normalize_state_list()

    state_attribute =
      module
      |> Spark.Dsl.Extension.get_opt([:state_machine], :state_attribute, nil)
      |> normalize_state_name()

    states_from_transitions =
      transitions
      |> Enum.flat_map(fn transition ->
        [Map.get(transition, :from), Map.get(transition, :to)]
      end)
      |> Enum.reject(&is_nil/1)

    states =
      (states_from_transitions ++ initial_states ++ terminal_states ++ [default_initial_state])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %{
      present: states != [] || transitions != [],
      states: states,
      transitions: transitions,
      state_attribute: state_attribute,
      initial_states: initial_states,
      default_initial_state: default_initial_state,
      terminal_states: terminal_states
    }
  rescue
    _ -> default_state_machine()
  end

  defp transition_entity_to_maps(transition) do
    action_name =
      transition
      |> Map.get(:action)
      |> normalize_action_name()

    from_states =
      transition
      |> Map.get(:from, [])
      |> normalize_state_list()

    to_states =
      transition
      |> Map.get(:to, [])
      |> normalize_state_list()

    for from_state <- from_states,
        to_state <- to_states do
      %{from: from_state, to: to_state}
      |> maybe_put_action(action_name)
    end
  end

  defp normalize_transition(transition) when is_map(transition) do
    from_state =
      transition
      |> Map.get(:from)
      |> normalize_state_name()

    to_state =
      transition
      |> Map.get(:to)
      |> normalize_state_name()

    action_name =
      transition
      |> Map.get(:action)
      |> normalize_action_name()

    if from_state && to_state do
      [
        %{from: from_state, to: to_state}
        |> maybe_put_action(action_name)
      ]
    else
      []
    end
  end

  defp normalize_transition(_transition), do: []

  defp normalize_state_list(list) when is_list(list) do
    list
    |> Enum.map(&normalize_state_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_state_list(value) do
    value
    |> normalize_state_name()
    |> case do
      nil -> []
      normalized -> [normalized]
    end
  end

  defp normalize_state_name(nil), do: nil
  defp normalize_state_name(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_state_name(value) when is_binary(value), do: value
  defp normalize_state_name(_value), do: nil

  defp normalize_action_name(nil), do: nil
  defp normalize_action_name(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_action_name(value) when is_binary(value), do: value
  defp normalize_action_name(_value), do: nil

  defp maybe_put_action(transition, nil), do: transition
  defp maybe_put_action(transition, action_name), do: Map.put(transition, :action, action_name)

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
