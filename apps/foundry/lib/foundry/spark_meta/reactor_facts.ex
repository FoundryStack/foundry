defmodule Foundry.SparkMeta.ReactorFacts do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis
  alias Foundry.SparkMeta.{Helpers, SourceContext, StepEntry, StepFacts}

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    classifier = Map.get(analysis.facts, :foundry_classifier, %{})

    if classifier[:type] in [:reactor, :transfer] do
      source_context = module_source_context(context)
      declared_side_effects = declared_step_side_effects(context.module)

      raw_steps =
        context.module
        |> fetch_reactor_steps()

      {steps, _step_outputs} =
        raw_steps
        |> Enum.with_index()
        |> Enum.map_reduce(%{}, fn {step, index}, step_outputs ->
          snippet = Map.get(source_context.step_sources, step.name)
          facts = derive_step_facts(snippet, source_context, step_outputs)
          target_action = Map.get(step, :action) |> then(&if &1, do: to_string(&1), else: nil)

          target_resource =
            List.first(facts.write_targets) ||
              List.first(facts.read_targets) ||
              Helpers.format_module_fqn(Map.get(step, :resource))

          entry = %StepEntry{
            name: step.name,
            type: step_type(step),
            description: Map.get(step, :description),
            target_module: Map.get(step, :impl) || Map.get(step, :resource),
            step_index: index,
            wait_for: Map.get(step, :wait_for, []) |> Enum.map(&to_string/1),
            has_compensation: Map.get(step, :compensate) != nil || Map.get(step, :undo_action) != nil,
            target_resource: target_resource,
            target_action: target_action,
            step_kind: derive_step_kind(step, facts),
            rules_applied: facts.rules_applied,
            source_snippet: snippet,
            read_targets: facts.read_targets,
            write_targets: facts.write_targets,
            fact_provenance: facts.provenance,
            side_effects:
              (declared_step_side_effects_for(step.name, declared_side_effects) ++
                 Foundry.SparkMeta.SideEffects.extract_side_effects_from_step(
                   snippet,
                   step.name
                 ))
              |> Enum.uniq()
          }

          next_outputs =
            Map.put(step_outputs, to_string(step.name), %{
              keys: facts.output_resources,
              direct: facts.direct_result_resources
            })

          {entry, next_outputs}
        end)

      {:ok, Analysis.put_fact(analysis, :foundry_reactor, %{steps: steps})}
    else
      {:ok, Analysis.put_fact(analysis, :foundry_reactor, %{steps: []})}
    end
  end

  def module_source_context(%SparkMeta.Context{} = context) do
    module_source_context(context.module, context.source_text)
  end

  def module_source_context(module, source_text \\ nil)

  def module_source_context(module, source_text) when is_binary(source_text) do
    with {:ok, module_context} <- extract_module_context(source_text, module) do
      %SourceContext{
        module: module,
        source_text: source_text,
        module_source: module_context.module_source,
        alias_map: extract_alias_map(module_context.module_source),
        step_sources: module_context.step_sources,
        helper_sources: module_context.helper_sources
      }
    else
      _ -> %SourceContext{module: module}
    end
  end

  def module_source_context(module, _source_text) do
    with path when is_binary(path) <- Helpers.module_source_path(module),
         {:ok, source_text} <- File.read(path) do
      module_source_context(module, source_text)
    else
      _ -> %SourceContext{module: module}
    end
  end

  defp fetch_reactor_steps(module) do
    try do
      module.entities([:reactor])
      |> Enum.filter(fn step ->
        struct_str = step.__struct__ |> Atom.to_string()

        is_struct(step) and
          (String.starts_with?(struct_str, "Elixir.Reactor.Dsl.Step") or
             String.starts_with?(struct_str, "Elixir.Reactor.Dsl.Reactor.Step") or
             String.starts_with?(struct_str, "Elixir.Ash.Reactor.Dsl"))
      end)
    rescue
      _ -> []
    end
  end

  defp step_type(step) do
    Map.get(step, :type)
    |> then(
      &if &1,
        do: to_string(&1),
        else: step.__struct__ |> Module.split() |> List.last() |> String.downcase()
    )
  rescue
    _ -> "unknown"
  end

  defp derive_step_kind(step, %StepFacts{} = facts) do
    cond do
      facts.write_targets != [] -> :write
      facts.read_targets != [] -> :read
      true -> derive_step_kind(step)
    end
  end

  defp derive_step_kind(step) do
    case step.__struct__ |> Module.split() |> List.last() do
      "Create" -> :write
      "Update" -> :write
      "Read" -> :read
      "ReadOne" -> :read
      "Map" -> :map
      _ -> :custom
    end
  rescue
    _ -> :custom
  end

  defp derive_step_facts(nil, _source_context, _step_outputs), do: %StepFacts{}

  defp derive_step_facts(snippet, %SourceContext{} = source_context, step_outputs) do
    alias_map = source_context.alias_map
    helper_facts = extract_local_helper_facts(snippet, source_context, MapSet.new())
    arg_provenance = extract_argument_provenance(snippet)

    variable_resources =
      snippet
      |> build_variable_resource_map(
        alias_map,
        step_outputs,
        arg_provenance,
        helper_facts.helper_results
      )
      |> merge_resource_maps(extract_helper_result_bindings(snippet, source_context))

    direct_facts = extract_resource_facts(snippet, alias_map, variable_resources)
    fallback_write_targets = infer_output_key_write_targets(snippet, arg_provenance, step_outputs)
    variable_input_targets = variable_resources |> Map.values() |> List.flatten() |> Enum.uniq()

    read_targets =
      (direct_facts.read_targets ++ helper_facts.read_targets ++ variable_input_targets)
      |> Enum.uniq()

    write_targets =
      (direct_facts.write_targets ++ helper_facts.write_targets ++ fallback_write_targets)
      |> Enum.uniq()

    rules_applied =
      snippet
      |> extract_rules_from_step_source(alias_map)
      |> Enum.uniq()

    output_resources = infer_step_output_resources(snippet, variable_resources)

    direct_result_resources =
      infer_direct_result_resources(snippet, variable_resources, read_targets, write_targets)

    %StepFacts{
      read_targets: read_targets,
      write_targets: write_targets,
      rules_applied: rules_applied,
      output_resources: output_resources,
      direct_result_resources: direct_result_resources,
      variable_resources: variable_resources,
      helper_results: helper_facts.helper_results,
      provenance: %{
        reads: Enum.into(read_targets, %{}, &{&1, :ast}),
        writes: Enum.into(write_targets, %{}, &{&1, :ast}),
        rules: Enum.into(rules_applied, %{}, &{&1, :ast}),
        policies: %{},
        queues: %{},
        external_calls: %{}
      }
    }
  end

  defp extract_module_context(source_text, module) do
    with {:ok, ast} <- Code.string_to_quoted(source_text),
         modules when is_list(modules) <- collect_module_definitions(ast, length(String.split(source_text, "\n"))),
         module_name <- Helpers.format_module_fqn(module),
         current when not is_nil(current) <- Enum.find(modules, &(&1.name == module_name)) do
      source_lines = String.split(source_text, "\n")

      module_source =
        source_lines
        |> Enum.slice((current.start_line - 1)..(current.end_line - 1))
        |> Enum.join("\n")

      body_nodes = normalize_block(current.body)

      {:ok,
       %{
         module_source: module_source,
         step_sources: collect_named_sources(body_nodes, :step),
         helper_sources: collect_named_sources(body_nodes, :def)
       }}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp collect_module_definitions(ast, total_lines) do
    forms = normalize_block(ast)

    raw_modules =
      forms
      |> Enum.flat_map(fn
        {:defmodule, meta, [module_ast, [do: body]]} ->
          [%{name: module_name(module_ast), start_line: meta[:line] || 1, body: body}]

        _ ->
          []
      end)

    raw_modules
    |> Enum.with_index()
    |> Enum.map(fn {mod, index} ->
      next_start =
        raw_modules
        |> Enum.at(index + 1)
        |> then(&if &1, do: &1.start_line, else: total_lines + 1)

      Map.put(mod, :end_line, next_start - 1)
    end)
  end

  defp collect_named_sources(nodes, macro_name) do
    nodes
    |> Enum.flat_map(fn node ->
      case node do
        {:step, _meta, args} when macro_name == :step ->
          [{extract_named_atom(args), Macro.to_string(node)}]

        {def_kind, _meta, [fn_ast | _]} when macro_name == :def and def_kind in [:def, :defp] ->
          [{extract_function_name(fn_ast), Macro.to_string(node)}]

        _ ->
          []
      end
    end)
    |> Enum.reject(fn {name, _source} -> is_nil(name) end)
    |> Enum.into(%{})
  end

  defp extract_argument_provenance(nil), do: %{}

  defp extract_argument_provenance(snippet) do
    [
      ~r/argument\s+:(\w+),\s*result\(:([\w_]+)(?:,\s*\[:(\w+)\])?\)/m,
      ~r/argument\(\s*:(\w+),\s*result\(\s*:(\w+)(?:,\s*\[:(\w+)\])?\)\s*\)/m
    ]
    |> Enum.flat_map(&Regex.scan(&1, snippet))
    |> Enum.into(%{}, fn
      [_, arg_name, step_name, key] -> {arg_name, %{step: step_name, key: blank_to_nil(key)}}
      [_, arg_name, step_name] -> {arg_name, %{step: step_name, key: nil}}
    end)
  end

  defp build_variable_resource_map(nil, _alias_map, _step_outputs, _arg_provenance, _helper_results), do: %{}

  defp build_variable_resource_map(snippet, alias_map, step_outputs, arg_provenance, helper_results) do
    arg_shapes =
      arg_provenance
      |> Enum.into(%{}, fn {arg_name, %{step: step_name, key: key}} ->
        shape =
          case Map.get(step_outputs, step_name, %{keys: %{}, direct: []}) do
            %{keys: keys, direct: direct} ->
              resources =
                cond do
                  is_binary(key) -> Map.get(keys, key, [])
                  true -> direct
                end

              %{direct: resources, keys: keys}

            _ ->
              %{direct: [], keys: %{}}
          end

        {arg_name, shape}
      end)

    from_args = Enum.map(arg_shapes, fn {arg_name, %{direct: resources}} -> {arg_name, resources} end)
    from_fn_params = extract_fn_param_bindings(snippet, arg_shapes)
    from_ash = extract_variable_bindings(snippet, alias_map)

    from_helpers =
      ~r/\{:ok,\s*(\w+)\}\s*<-\s*(\w+)\(/m
      |> Regex.scan(snippet)
      |> Enum.flat_map(fn [_, variable, helper_name] ->
        case Map.get(helper_results, helper_name, []) do
          [] -> []
          resources -> [{variable, resources}]
        end
      end)

    (from_args ++ from_fn_params ++ from_ash ++ from_helpers)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.into(%{}, fn {var, resource_lists} ->
      {var, resource_lists |> List.flatten() |> Enum.uniq()}
    end)
  end

  defp extract_variable_bindings(snippet, alias_map) do
    patterns = [
      ~r/\{:ok,\s*(\w+)\}\s*<-\s*Ash\.(?:get|create|update|destroy)\(\s*([^,\s)]+)/m,
      ~r/\{:ok,\s*\[(\w+)\s*\|\s*_\]\}\s*<-\s*Ash\.read\(\s*([^,\s)]+)/m
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, snippet)
      |> Enum.map(fn [_, variable, resource_ref] ->
        {variable, resolve_resource_ref(resource_ref, alias_map)}
      end)
    end)
    |> Enum.reject(fn {_variable, resource} -> is_nil(resource) end)
    |> Enum.map(fn {variable, resource} -> {variable, [resource]} end)
  end

  defp extract_resource_facts(nil, _alias_map, _variable_resources), do: %StepFacts{}

  defp extract_resource_facts(snippet, alias_map, variable_resources) do
    read_targets = extract_resource_refs(snippet, ~r/Ash\.(?:get|read)\(\s*([^,\s)]+)/, alias_map)

    explicit_write_targets =
      extract_resource_refs(snippet, ~r/Ash\.(?:create|update|destroy)\(\s*([^,\s)]+)/, alias_map)

    variable_write_targets =
      ~r/Ash\.(?:update|destroy)\(\s*(\w+),/
      |> Regex.scan(snippet)
      |> Enum.flat_map(fn [_, variable] -> Map.get(variable_resources, variable, []) end)

    %StepFacts{
      read_targets: Enum.uniq(read_targets),
      write_targets: Enum.uniq(explicit_write_targets ++ variable_write_targets)
    }
  end

  defp extract_rules_from_step_source(nil, _alias_map), do: []

  defp extract_rules_from_step_source(snippet, alias_map) do
    explicit =
      ~r/([A-Z][A-Za-z0-9._]*\.Rules\.[A-Z][A-Za-z0-9._]*)/
      |> Regex.scan(snippet)
      |> Enum.map(&List.first/1)
      |> Enum.uniq()

    aliased =
      alias_map
      |> Enum.filter(fn {short, full} ->
        String.contains?(full, ".Rules.") and
          (String.contains?(snippet, short <> ".evaluate(") or
             String.contains?(snippet, short <> ".check("))
      end)
      |> Enum.map(fn {_short, full} -> full end)

    Enum.uniq(explicit ++ aliased)
  end

  defp infer_step_output_resources(nil, _variable_resources), do: %{}

  defp infer_step_output_resources(snippet, variable_resources) do
    snippet
    |> extract_ok_result_maps()
    |> Enum.reduce(%{}, fn result_map, acc ->
      Map.merge(acc, extract_output_resources_from_result_map(result_map, variable_resources))
    end)
  end

  defp infer_direct_result_resources(nil, _variable_resources, _read_targets, _write_targets), do: []

  defp infer_direct_result_resources(snippet, variable_resources, read_targets, write_targets) do
    direct =
      snippet
      |> extract_ok_result_variables()
      |> Enum.flat_map(fn variable -> Map.get(variable_resources, variable, []) end)
      |> Enum.uniq()

    cond do
      direct != [] -> direct
      count_resource_targets(read_targets, write_targets) == 1 -> read_targets ++ write_targets
      true -> []
    end
  end

  defp extract_local_helper_facts(nil, _source_context, _seen), do: %StepFacts{}

  defp extract_local_helper_facts(snippet, %SourceContext{} = source_context, seen) do
    helper_names = Map.keys(source_context.helper_sources)

    snippet
    |> extract_local_function_calls(helper_names)
    |> Enum.reject(&MapSet.member?(seen, &1))
    |> Enum.reduce(%StepFacts{}, fn helper_name, acc ->
      helper_source = Map.get(source_context.helper_sources, helper_name)
      next_seen = MapSet.put(seen, helper_name)
      nested = extract_local_helper_facts(helper_source, source_context, next_seen)
      direct = extract_resource_facts(helper_source, source_context.alias_map, %{})
      helper_variable_resources = build_variable_resource_map(helper_source, source_context.alias_map, %{}, %{}, %{})

      helper_results =
        infer_direct_result_resources(
          helper_source,
          helper_variable_resources,
          direct.read_targets,
          direct.write_targets
        )

      %StepFacts{
        read_targets: Enum.uniq(acc.read_targets ++ direct.read_targets ++ nested.read_targets),
        write_targets: Enum.uniq(acc.write_targets ++ direct.write_targets ++ nested.write_targets),
        direct_result_resources:
          Enum.uniq(acc.direct_result_resources ++ helper_results ++ nested.direct_result_resources),
        helper_results:
          acc.helper_results
          |> Map.merge(%{helper_name => helper_results})
          |> Map.merge(nested.helper_results)
      }
    end)
  end

  defp extract_local_function_calls(snippet, helper_names) do
    ~r/\b([a-z_][a-zA-Z0-9_]*)\(/m
    |> Regex.scan(snippet)
    |> Enum.map(fn [_, helper_name] -> helper_name end)
    |> Enum.filter(&(&1 in helper_names))
    |> Enum.uniq()
  end

  defp extract_helper_result_bindings(nil, _source_context), do: %{}

  defp extract_helper_result_bindings(snippet, %SourceContext{} = source_context) do
    helper_names = Map.keys(source_context.helper_sources)

    ~r/\{:ok,\s*(\w+)\}\s*<-\s*(\w+)\(/m
    |> Regex.scan(snippet)
    |> Enum.reduce(%{}, fn [_, variable, helper_name], acc ->
      if helper_name in helper_names do
        helper_source = Map.get(source_context.helper_sources, helper_name)
        helper_variable_resources = build_variable_resource_map(helper_source, source_context.alias_map, %{}, %{}, %{})
        direct = extract_resource_facts(helper_source, source_context.alias_map, helper_variable_resources)

        resources =
          infer_direct_result_resources(
            helper_source,
            helper_variable_resources,
            direct.read_targets,
            direct.write_targets
          )

        if resources == [] do
          acc
        else
          Map.update(acc, variable, resources, &(Enum.uniq(&1 ++ resources)))
        end
      else
        acc
      end
    end)
  end

  defp merge_resource_maps(left, right) do
    Map.merge(left, right, fn _key, left_resources, right_resources ->
      Enum.uniq(left_resources ++ right_resources)
    end)
  end

  defp infer_output_key_write_targets(nil, _arg_provenance, _step_outputs), do: []

  defp infer_output_key_write_targets(snippet, arg_provenance, step_outputs) do
    updated_variables =
      ~r/Ash\.(?:update|destroy)\(\s*(\w+),/
      |> Regex.scan(snippet)
      |> Enum.map(fn [_, variable] -> variable end)
      |> Enum.uniq()

    arg_provenance
    |> Enum.flat_map(fn {_arg_name, %{step: step_name}} ->
      case Map.get(step_outputs, step_name, %{keys: %{}}) do
        %{keys: keys} -> Enum.flat_map(updated_variables, &Map.get(keys, &1, []))
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp declared_step_side_effects(module) do
    case module.__info__(:attributes)[:step_side_effects] do
      [map] when is_map(map) -> map
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  defp declared_step_side_effects_for(step_name, declared_side_effects) do
    Map.get(declared_side_effects, step_name, [])
    |> Enum.map(fn side_effect ->
      %Foundry.SparkMeta.SideEffectEntry{
        type: side_effect.type,
        name: to_string(side_effect[:name] || ""),
        declared: true,
        declared_on: :module_attribute,
        idempotent: side_effect[:idempotent],
        idempotency_key_from: normalize_step_side_effect_key(side_effect[:idempotency_key_from] || side_effect[:key_from]),
        epistemic: "DECLARED",
        step_name: to_string(step_name)
      }
    end)
  end

  defp extract_alias_map(nil), do: %{}

  defp extract_alias_map(module_source) do
    grouped =
      ~r/alias\s+([A-Z][A-Za-z0-9_.]*)\.\{([^}]+)\}/
      |> Regex.scan(module_source)
      |> Enum.flat_map(fn [_, prefix, grouped_aliases] ->
        grouped_aliases
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn alias_name -> {alias_name, prefix <> "." <> alias_name} end)
      end)

    singles =
      module_source
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(String.starts_with?(&1, "alias ") and not String.contains?(&1, "{")))
      |> Enum.map(fn line ->
        line
        |> String.replace_prefix("alias ", "")
        |> String.split("#")
        |> List.first()
        |> String.trim()
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn full ->
        short = full |> String.split(".") |> List.last()
        {short, full}
      end)

    Map.new(grouped ++ singles)
  end

  defp extract_resource_refs(snippet, pattern, alias_map) do
    Regex.scan(pattern, snippet)
    |> Enum.map(fn [_, resource_ref] -> resolve_resource_ref(resource_ref, alias_map) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp resolve_resource_ref(resource_ref, alias_map) do
    resource_ref = String.trim(resource_ref)

    cond do
      String.starts_with?(resource_ref, "IgamingRef.") -> resource_ref
      String.starts_with?(resource_ref, "Foundry.") -> resource_ref
      Map.has_key?(alias_map, resource_ref) -> Map.get(alias_map, resource_ref)
      Regex.match?(~r/^[A-Z][A-Za-z0-9_.]*$/, resource_ref) -> resource_ref
      true -> nil
    end
  end

  defp normalize_block({:__block__, _, forms}), do: forms
  defp normalize_block(nil), do: []
  defp normalize_block(form), do: [form]

  defp module_name({:__aliases__, _, parts}), do: Enum.join(parts, ".")
  defp module_name(module) when is_atom(module), do: Helpers.format_module_fqn(module)
  defp module_name(_module), do: nil

  defp extract_named_atom(args) when is_list(args) do
    Enum.find_value(args, fn
      atom when is_atom(atom) -> atom
      _ -> nil
    end)
  end

  defp extract_named_atom(_args), do: nil
  defp extract_function_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp extract_function_name(_function), do: nil

  defp count_resource_targets(read_targets, write_targets) do
    (read_targets ++ write_targets) |> Enum.uniq() |> length()
  end

  defp normalize_step_side_effect_key(nil), do: []
  defp normalize_step_side_effect_key(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_step_side_effect_key(key), do: [to_string(key)]

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp extract_fn_param_bindings(nil, _arg_shapes), do: []

  defp extract_fn_param_bindings(snippet, arg_shapes) do
    with {:ok, ast} <- Code.string_to_quoted(snippet) do
      {_ast, bindings} =
        Macro.prewalk(ast, [], fn
          {:fn, _, clauses} = node, acc ->
            clause_bindings =
              Enum.flat_map(clauses, fn
                {:->, _, [[pattern | _], _body]} -> bind_param_pattern(pattern, arg_shapes)
                _ -> []
              end)

            {node, acc ++ clause_bindings}

          node, acc ->
            {node, acc}
        end)

      bindings
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp bind_param_pattern({:%{}, _, fields}, arg_shapes) do
    Enum.flat_map(fields, fn {key_ast, value_ast} ->
      key = pattern_key_name(key_ast)

      case Map.get(arg_shapes, key) do
        nil -> []
        shape -> bind_pattern_value(value_ast, shape)
      end
    end)
  end

  defp bind_param_pattern(_pattern, _arg_shapes), do: []

  defp bind_pattern_value(variable_ast, %{direct: resources}) do
    case variable_name(variable_ast) do
      nil -> []
      name -> if resources == [], do: [], else: [{name, resources}]
    end
  end

  defp bind_pattern_value({:%{}, _, fields}, %{keys: keys}) do
    Enum.flat_map(fields, fn {key_ast, value_ast} ->
      key = pattern_key_name(key_ast)
      resources = Map.get(keys, key, [])
      bind_pattern_value(value_ast, %{direct: resources, keys: %{}})
    end)
  end

  defp bind_pattern_value(_value_ast, _shape), do: []
  defp pattern_key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp pattern_key_name(key) when is_binary(key), do: key
  defp pattern_key_name(_key), do: nil

  defp extract_ok_result_maps(nil), do: []

  defp extract_ok_result_maps(snippet) do
    with {:ok, ast} <- Code.string_to_quoted(snippet) do
      {_ast, maps} =
        Macro.prewalk(ast, [], fn
          {:ok, {:%{}, _, fields}} = node, acc -> {node, [fields | acc]}
          node, acc -> {node, acc}
        end)

      Enum.reverse(maps)
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp extract_output_resources_from_result_map(result_fields, variable_resources) do
    Enum.reduce(result_fields, %{}, fn
      {key_ast, value_ast}, acc ->
        key = pattern_key_name(key_ast)
        variable = variable_name(value_ast)

        case variable && Map.get(variable_resources, variable, []) do
          [] -> acc
          resources -> Map.put(acc, key, resources)
        end
    end)
  end

  defp extract_ok_result_variables(nil), do: []

  defp extract_ok_result_variables(snippet) do
    with {:ok, ast} <- Code.string_to_quoted(snippet) do
      {_ast, variables} =
        Macro.prewalk(ast, [], fn
          {:ok, value_ast} = node, acc ->
            case variable_name(value_ast) do
              nil -> {node, acc}
              variable -> {node, [variable | acc]}
            end

          node, acc ->
            {node, acc}
        end)

      variables |> Enum.reverse() |> Enum.uniq()
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp variable_name({var, _, context}) when is_atom(var) and (is_atom(context) or is_nil(context)) do
    Atom.to_string(var)
  end

  defp variable_name(_ast), do: nil
end
