defmodule Foundry.Context.ScenarioExtractor do
  @moduledoc """
  Extracts Studio scenarios from test source.

  Real executable test calls are the primary source of truth. Optional
  `@scenario` metadata provides category, compliance links, labels, and exact
  focus hints where inference is ambiguous.
  """

  alias Foundry.Context.ScenarioEntry

  @ash_funs ~w(get read read_one create update destroy)a

  def extract(project_root, nodes_map) do
    test_dir = Path.join(project_root, "test")

    if File.dir?(test_dir) do
      test_dir
      |> Path.join("**/*.{exs,ex}")
      |> Path.wildcard()
      |> Enum.flat_map(&extract_file(&1, nodes_map))
    else
      []
    end
  end

  defp extract_file(file_path, nodes_map) do
    with {:ok, content} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(content) do
      node_lookup = build_node_lookup(nodes_map)
      alias_map = extract_alias_map(ast)
      source_module = extract_module_name(ast)
      extract_from_ast(ast, source_module, file_path, alias_map, node_lookup)
    else
      _ -> []
    end
  end

  defp extract_module_name({:defmodule, _meta, [{:__aliases__, _am, parts}, _body]}),
    do: Enum.join(parts, ".")

  defp extract_module_name({:__block__, _meta, forms}) do
    forms
    |> Enum.find_value(fn
      {:defmodule, _, [{:__aliases__, _, parts}, _]} -> Enum.join(parts, ".")
      _ -> nil
    end)
    |> Kernel.||("UnknownModule")
  end

  defp extract_module_name(_), do: "UnknownModule"

  defp extract_from_ast(ast, source_module, file_path, alias_map, node_lookup) do
    Macro.prewalk(ast, [], fn
      {:describe, _meta, [describe_name, [do: body]]} = node, acc ->
        {node,
         acc ++
           extract_scenarios_from_describe(
             describe_name,
             body,
             source_module,
             file_path,
             alias_map,
             node_lookup
           )}

      {:describe, _meta, [describe_name, body]} = node, acc ->
        {node,
         acc ++
           extract_scenarios_from_describe(
             describe_name,
             body,
             source_module,
             file_path,
             alias_map,
             node_lookup
           )}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp extract_scenarios_from_describe(
         describe_name,
         body,
         source_module,
         file_path,
         alias_map,
         node_lookup
       ) do
    scenario_meta = extract_scenario_metadata(body)
    category = first_present(scenario_meta, [:category])

    if is_nil(category) do
      []
    else
      flow =
        case normalize_flow(first_present(scenario_meta, [:flow]), node_lookup) do
          [] -> infer_flow(body, alias_map, node_lookup)
          steps -> steps
        end

      if flow == [] do
        []
      else
        [{nodes, graph_path}] = [derive_flow_summaries(flow)]

        [
          %ScenarioEntry{
            id: generate_scenario_id(source_module, describe_name),
            name: describe_name,
            category: category,
            source_file: file_path,
            source_module: source_module,
            nodes: nodes,
            graph_path: graph_path,
            compliance_links:
              normalize_string_list(first_present(scenario_meta, [:compliance_links])),
            flow: flow,
            tags: normalize_tags(first_present(scenario_meta, [:tags]) || [])
          }
        ]
      end
    end
  end

  defp extract_scenario_metadata(body) do
    Macro.prewalk(body, [], fn
      {:@, _meta, [{:scenario, _, [value]}]} = node, acc ->
        {node, [normalize_scenario_attr(value) | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  defp normalize_scenario_attr(value) do
    case literal_value(value) do
      literal when is_map(literal) ->
        literal

      literal when is_list(literal) ->
        if Keyword.keyword?(literal), do: Map.new(literal), else: %{}

      _ ->
        %{}
    end
  end

  defp normalize_flow(nil, _node_lookup), do: []
  defp normalize_flow(flow, _node_lookup) when flow in [%{}, []], do: []

  defp normalize_flow(flow, node_lookup) when is_list(flow) do
    flow
    |> Enum.with_index()
    |> Enum.map(fn {step, index} -> normalize_flow_step(step, index, node_lookup) end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_flow(_flow, _node_lookup), do: []

  defp normalize_flow_step(step, index, node_lookup) when is_map(step) do
    node_id =
      step
      |> first_present([:node_id, :node])
      |> resolve_optional_node_id(node_lookup)

    focus_node_id =
      step
      |> first_present([:focus_node_id, :graph_node, :graph_node_id])
      |> normalize_focus_override(node_id, node_lookup)
      |> Kernel.||(
        resolve_step_focus(
          node_id,
          first_present(step, [:step_name, :focus_step_name]),
          node_lookup
        )
      )
      |> Kernel.||(node_id)

    focus_targets =
      step
      |> explicit_focus_targets(node_lookup)
      |> case do
        [] ->
          step
          |> first_present([:next_nodes])
          |> normalize_string_list()
          |> Enum.map(&resolve_node_id(&1, node_lookup))
          |> Enum.reject(&is_nil/1)

        targets ->
          targets
      end

    %{
      id: normalize_optional_string(first_present(step, [:id])) || "step-#{index + 1}",
      type: first_present(step, [:type]) || infer_flow_type(index),
      label:
        normalize_optional_string(first_present(step, [:label])) ||
          default_flow_label(focus_node_id || node_id, index),
      node_id: node_id,
      focus_node_id: focus_node_id,
      focus_targets: focus_targets,
      emits: normalize_string_list(first_present(step, [:emits])),
      reacts_to: normalize_optional_string(first_present(step, [:reacts_to])),
      action: normalize_optional_string(first_present(step, [:action, :action_or_event])),
      actor: normalize_optional_string(first_present(step, [:actor])),
      details: normalize_optional_string(first_present(step, [:details]))
    }
  end

  defp normalize_flow_step(_step, _index, _node_lookup), do: nil

  defp infer_flow(body, alias_map, node_lookup) do
    body
    |> extract_test_blocks()
    |> Enum.flat_map(&collect_calls(&1, alias_map, node_lookup))
    |> Enum.uniq_by(fn step -> {step.node_id, step.focus_node_id, step.action, step.label} end)
    |> attach_focus_targets()
  end

  defp extract_test_blocks(body) do
    Macro.prewalk(body, [], fn
      {:test, _meta, [_name, [do: block]]} = node, acc -> {node, [block | acc]}
      {:property, _meta, [_name, [do: block]]} = node, acc -> {node, [block | acc]}
      node, acc -> {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp collect_calls(block, alias_map, node_lookup) do
    Macro.prewalk(block, [], fn
      {{:., _, [module_ast, fun]}, _meta, args} = node, acc ->
        step =
          infer_call_step(module_ast, fun, args || [], alias_map, node_lookup, length(acc))

        {node, if(step, do: [step | acc], else: acc)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp infer_call_step(module_ast, fun, args, alias_map, node_lookup, index) do
    module_name = resolve_module_name(module_ast, alias_map)
    fun_name = to_string(fun)

    cond do
      module_name == "Ash" and fun in @ash_funs ->
        infer_ash_step(fun_name, args, node_lookup, index)

      is_nil(module_name) ->
        nil

      resolved_node = resolve_node_id(module_name, node_lookup) ->
        infer_module_step(resolved_node, fun_name, node_lookup, index)

      true ->
        nil
    end
  end

  defp infer_ash_step(fun_name, [resource_ast | rest], node_lookup, index) do
    resource_name = resolve_module_name(resource_ast, %{})
    node_id = resolve_node_id(resource_name, node_lookup)

    if node_id do
      action =
        case rest do
          [action_ast | _] -> extract_action_name(action_ast)
          _ -> nil
        end

      focus_node_id =
        case action do
          nil -> node_id
          action_name -> build_action_focus(node_id, action_name, node_lookup)
        end

      %{
        id: "step-#{index + 1}",
        type: if(index == 0, do: :entry, else: :reaction),
        label: ash_step_label(fun_name, node_id, action),
        node_id: node_id,
        focus_node_id: focus_node_id,
        focus_targets: [],
        emits: [],
        reacts_to: nil,
        action: action,
        actor: nil,
        details: nil
      }
    end
  end

  defp infer_ash_step(_fun_name, _args, _node_lookup, _index), do: nil

  defp infer_module_step(node_id, fun_name, node_lookup, index) do
    node = Map.get(node_lookup.by_id, node_id)
    short_name = List.last(String.split(node_id, "."))

    {type, action} =
      cond do
        match?(%{type: "rule"}, node) and fun_name == "evaluate" -> {:assertion, "evaluate"}
        match?(%{type: "job"}, node) and fun_name == "perform" -> {:job, fun_name}
        fun_name == "handle_webhook" -> {:entry, fun_name}
        index == 0 -> {:entry, fun_name}
        true -> {:reaction, fun_name}
      end

    %{
      id: "step-#{index + 1}",
      type: type,
      label: infer_module_label(type, short_name, fun_name),
      node_id: node_id,
      focus_node_id: infer_module_focus(node_id, node, fun_name, node_lookup),
      focus_targets: [],
      emits: [],
      reacts_to: nil,
      action: action,
      actor: nil,
      details: nil
    }
  end

  defp infer_module_focus(node_id, %{type: type} = node, fun_name, node_lookup)
       when type in ["resource", "job", "rule"] do
    case build_action_focus(node_id, fun_name, node_lookup) do
      nil -> node.id
      action_focus -> action_focus
    end
  end

  defp infer_module_focus(node_id, %{type: type}, fun_name, node_lookup)
       when type in ["transfer", "reactor"] do
    resolve_step_focus(node_id, fun_name, node_lookup) || node_id
  end

  defp infer_module_focus(node_id, _node, _fun_name, _node_lookup), do: node_id

  defp attach_focus_targets(steps) do
    steps
    |> Enum.with_index()
    |> Enum.map(fn {step, index} ->
      next_focus =
        steps
        |> Enum.at(index + 1)
        |> case do
          nil -> []
          next_step -> [next_step.focus_node_id || next_step.node_id] |> Enum.reject(&is_nil/1)
        end

      %{step | focus_targets: next_focus}
    end)
  end

  defp derive_flow_summaries(flow) do
    nodes =
      flow
      |> Enum.flat_map(fn step ->
        [step.node_id | Enum.map(step.focus_targets, &base_node_id/1)]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    graph_path =
      flow
      |> Enum.flat_map(fn step ->
        [step.focus_node_id || step.node_id | step.focus_targets]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {nodes, graph_path}
  end

  defp extract_alias_map(ast) do
    Macro.prewalk(ast, %{}, fn
      {:alias, _meta, args} = node, acc ->
        {node, merge_alias_map(acc, alias_entries_from_ast(args))}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp alias_entries_from_ast([{:__aliases__, _, base}, [do: {:__block__, _, nested}]]) do
    Enum.flat_map(nested, fn
      {:__aliases__, _, [leaf]} ->
        [{to_string(leaf), Enum.join(base ++ [leaf], ".")}]

      _ ->
        []
    end)
  end

  defp alias_entries_from_ast([{:__aliases__, _, parts}]), do: default_alias_entry(parts)

  defp alias_entries_from_ast([{:__aliases__, _, parts}, opts]) when is_list(opts) do
    explicit_alias = Keyword.get(opts, :as)

    if explicit_alias do
      [{alias_name(explicit_alias), Enum.join(parts, ".")}]
    else
      default_alias_entry(parts)
    end
  end

  defp alias_entries_from_ast(_args), do: []

  defp default_alias_entry(parts) do
    [{List.last(parts) |> to_string(), Enum.join(parts, ".")}]
  end

  defp alias_name({:__aliases__, _, parts}), do: List.last(parts) |> to_string()
  defp alias_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp alias_name(other), do: to_string(other)

  defp merge_alias_map(left, right), do: Map.merge(left, Map.new(right))

  defp resolve_module_name({:__aliases__, _, parts}, alias_map) do
    parts
    |> Enum.map(&to_string/1)
    |> resolve_alias_parts(alias_map)
  end

  defp resolve_module_name(atom, _alias_map) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp resolve_module_name(binary, _alias_map) when is_binary(binary), do: binary
  defp resolve_module_name(_, _alias_map), do: nil

  defp resolve_alias_parts([head | tail], alias_map) do
    case Map.get(alias_map, head) do
      nil -> Enum.join([head | tail], ".")
      resolved when tail == [] -> resolved
      resolved -> Enum.join([resolved | tail], ".")
    end
  end

  defp resolve_alias_parts([], _alias_map), do: nil

  defp build_node_lookup(nodes) do
    by_id = Map.new(nodes, &{&1.id, &1})

    aliases =
      nodes
      |> Enum.flat_map(fn node ->
        module_name = node.module || node.id
        parts = String.split(module_name, ".")
        short = List.last(parts)
        domain_short = parts |> Enum.take(-2) |> Enum.join(".")
        id_short = node.id |> String.replace_prefix((List.first(parts) || "") <> ".", "")

        [
          {module_name, node.id},
          {node.id, node.id},
          {short, node.id},
          {domain_short, node.id},
          {id_short, node.id}
        ]
      end)
      |> Enum.reject(fn {key, _value} -> is_nil(key) or key == "" end)
      |> Enum.into(%{})

    %{by_id: by_id, aliases: aliases}
  end

  defp resolve_node_id(nil, _node_lookup), do: nil

  defp resolve_node_id(node_name, node_lookup) do
    normalized = stringify(node_name)

    cond do
      Map.has_key?(node_lookup.aliases, normalized) ->
        Map.fetch!(node_lookup.aliases, normalized)

      Map.has_key?(node_lookup.by_id, normalized) ->
        normalized

      true ->
        nil
    end
  end

  defp resolve_optional_node_id(nil, _node_lookup), do: nil

  defp resolve_optional_node_id(node_name, node_lookup),
    do: resolve_node_id(node_name, node_lookup)

  defp resolve_step_focus(nil, _step_name, _node_lookup), do: nil
  defp resolve_step_focus(_node_id, nil, _node_lookup), do: nil

  defp resolve_step_focus(node_id, step_name, node_lookup) do
    case Map.get(node_lookup.by_id, node_id) do
      %{steps: steps} when is_list(steps) ->
        steps
        |> Enum.with_index()
        |> Enum.find_value(fn {step, index} ->
          current_name = Map.get(step, :name) || Map.get(step, "name")

          if normalize_name(current_name) == normalize_name(step_name) do
            "#{node_id}:step:#{index}"
          end
        end)

      _ ->
        nil
    end
  end

  defp normalize_focus_override(nil, _node_id, _node_lookup), do: nil

  defp normalize_focus_override(focus_value, node_id, node_lookup) do
    graph_id = stringify(focus_value)

    cond do
      node_id && String.starts_with?(graph_id, ":step:") ->
        "#{node_id}#{graph_id}"

      node_id && String.starts_with?(graph_id, ":action:") ->
        "#{node_id}#{graph_id}"

      String.contains?(graph_id, ":step:") ->
        [base, suffix] = String.split(graph_id, ":step:", parts: 2)
        "#{resolve_node_id(base, node_lookup)}:step:#{suffix}"

      String.contains?(graph_id, ":action:") ->
        [base, suffix] = String.split(graph_id, ":action:", parts: 2)
        "#{resolve_node_id(base, node_lookup)}:action:#{suffix}"

      true ->
        resolve_node_id(graph_id, node_lookup)
    end
  end

  defp explicit_focus_targets(step, node_lookup) do
    explicit_targets =
      step
      |> first_present([:focus_targets, :next_graph_nodes])
      |> normalize_string_list()

    resolved_explicit_targets =
      explicit_targets
      |> Enum.map(&normalize_focus_override(&1, nil, node_lookup))
      |> Enum.reject(&is_nil/1)

    step_names =
      step
      |> first_present([:next_step_names])
      |> normalize_string_list()

    if step_names == [] do
      resolved_explicit_targets
    else
      base_targets =
        if explicit_targets != [] do
          explicit_targets
          |> Enum.map(&resolve_node_id(&1, node_lookup))
        else
          step
          |> first_present([:next_nodes])
          |> normalize_string_list()
          |> Enum.map(&resolve_node_id(&1, node_lookup))
        end

      base_targets
      |> Enum.zip(step_names)
      |> Enum.map(fn {next_node_id, step_name} ->
        resolve_step_focus(next_node_id, step_name, node_lookup) || next_node_id
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  defp build_action_focus(node_id, action_name, node_lookup) do
    case Map.get(node_lookup.by_id, node_id) do
      %{actions: actions} when is_list(actions) ->
        normalized_action = normalize_name(action_name)

        if Enum.any?(actions, fn action ->
             current = Map.get(action, :name) || Map.get(action, "name")
             normalize_name(current) == normalized_action
           end) do
          "#{node_id}:action:#{action_name}"
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp extract_action_name(action_ast) do
    case literal_value(action_ast) do
      action when is_atom(action) -> Atom.to_string(action)
      action when is_binary(action) -> action
      _ -> nil
    end
  end

  defp ash_step_label(fun_name, node_id, action) do
    short = List.last(String.split(node_id, "."))

    case {fun_name, action} do
      {"get", _} -> "Load #{short}"
      {"read", _} -> "Read #{short}"
      {"read_one", _} -> "Read #{short}"
      {"create", nil} -> "Create #{short}"
      {"create", act} -> "Create #{short} via #{act}"
      {"update", nil} -> "Update #{short}"
      {"update", act} -> "Update #{short} via #{act}"
      {"destroy", nil} -> "Destroy #{short}"
      {"destroy", act} -> "Destroy #{short} via #{act}"
      _ -> "#{String.capitalize(fun_name)} #{short}"
    end
  end

  defp infer_module_label(:assertion, short_name, _fun_name), do: "Evaluate #{short_name}"
  defp infer_module_label(:job, short_name, _fun_name), do: "Run #{short_name}"

  defp infer_module_label(:entry, short_name, "handle_webhook"),
    do: "Handle #{short_name} webhook"

  defp infer_module_label(:entry, short_name, fun_name),
    do: "#{String.capitalize(fun_name)} #{short_name}"

  defp infer_module_label(_type, short_name, fun_name),
    do: "#{String.capitalize(fun_name)} #{short_name}"

  defp infer_flow_type(0), do: :entry
  defp infer_flow_type(_index), do: :reaction

  defp default_flow_label(nil, index), do: "Step #{index + 1}"

  defp default_flow_label(node_id, _index) do
    short = node_id |> base_node_id() |> String.split(".") |> List.last()
    "Visit #{short}"
  end

  defp generate_scenario_id(source_module, describe_name) do
    suffix =
      describe_name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")

    "#{source_module}.#{suffix}"
  end

  defp normalize_tags(tags) when is_list(tags) do
    Enum.filter(tags, &is_atom/1)
  end

  defp normalize_tags(_tags), do: []

  defp first_present(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  defp literal_value({:%{}, _meta, pairs}) do
    pairs
    |> Enum.map(fn {key, value} -> {literal_value(key), literal_value(value)} end)
    |> Map.new()
  end

  defp literal_value({:__aliases__, _meta, parts}), do: Enum.join(parts, ".")

  defp literal_value({:{}, _meta, values}) do
    values
    |> Enum.map(&literal_value/1)
    |> List.to_tuple()
  end

  defp literal_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.map(list, fn {key, value} -> {key, literal_value(value)} end)
    else
      Enum.map(list, &literal_value/1)
    end
  end

  defp literal_value(value), do: value

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(value) do
    value
    |> normalize_optional_string()
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value), do: to_string(value)

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: to_string(value)

  defp normalize_name(nil), do: nil
  defp normalize_name(value), do: value |> stringify() |> String.trim_leading(":")

  defp base_node_id(nil), do: nil

  defp base_node_id(graph_id) do
    graph_id
    |> stringify()
    |> String.split(":step:", parts: 2)
    |> List.first()
    |> String.split(":action:", parts: 2)
    |> List.first()
  end
end
