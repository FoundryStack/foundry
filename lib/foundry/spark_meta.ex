defmodule Foundry.SparkMeta.ModuleInfo do
  @moduledoc """
  Output struct from SparkMeta.walk/1.

  Mirrors the NodeEntry schema fields that SparkMeta can derive without Foundry-specific context.
  Fields like :sensitive (which requires manifest access) are absent — those are added by NodeBuilder.
  """

  @derive Jason.Encoder
  @enforce_keys [:module]
  defstruct [
    :module,
    # :resource | :transfer | :reactor | :rule | :job |
    type: nil,
    # :blueprint | :provider | :liveview | :liveresource | :agent
    description: nil,
    attributes: [],
    actions: [],
    rules: [],
    compliance: [],
    adrs: [],
    runbook: nil,
    data_layer: nil,
    paper_trail: false,
    archival: false,
    state_machine: %{present: false, states: [], transitions: [], state_attribute: nil, initial_states: [], default_initial_state: nil, terminal_states: []},
    api_routes: [],
    telemetry_prefix: [],
    money_attributes: [],
    authentication_subject: false,
    oban_queues: [],
    rate_limited: false,
    feature_flags: [],
    steps: [],
    outputs: [],
    agent_steps: [],
    performs: nil,
    last_modified: nil,
    relationships: [],
    auth_strategies: [],
    side_effects: [],
    trigger_kind: nil
  ]
end

defmodule Foundry.SparkMeta.Attribute do
  @moduledoc "Structured representation of an Ash resource attribute."
  @derive Jason.Encoder
  defstruct [
    :name,
    :type,
    :description,
    pii: false,
    sensitive: false,
    money: false,
    cldr_backend: nil
  ]

end

defmodule Foundry.SparkMeta.Action do
  @moduledoc "Structured representation of an Ash resource action."
  @derive Jason.Encoder
  defstruct [:name, :type, :description]

end

defmodule Foundry.SparkMeta.StepEntry do
  @moduledoc """
  Structured representation of a Reactor step.

  For `:agent` steps (ash_ai v0.6 `run prompt(...)` syntax), the following
  additional fields are populated:
  - `step_model` — LLM model string (e.g. "anthropic:claude-sonnet-4-6")
  - `confidence_threshold` — float e.g. 0.8
  - `on_low_confidence` — atom: `:escalate_human`, `:abort`, `:retry`
  - `step_tools` — list of tool atoms passed to `run prompt(...)`
  - `step_telemetry_prefix` — list of atoms for telemetry prefix
  """
  @derive Jason.Encoder
  defstruct [
    :name,
    :type,
    :description,
    :target_module,
    step_index: nil,
    wait_for: [],
    has_compensation: false,
    target_resource: nil,
    target_action: nil,
    step_kind: nil,
    rules_applied: [],
    source_snippet: nil,
    read_targets: [],
    write_targets: [],
    fact_provenance: %{},
    # ash_ai v0.6 agent step fields (INV-014..017)
    step_model: nil,
    confidence_threshold: nil,
    on_low_confidence: nil,
    step_tools: [],
    step_telemetry_prefix: [],
    side_effects: []
  ]

end

defmodule Foundry.SparkMeta.SideEffectEntry do
  @moduledoc """
  Structured representation of a side effect.

  Corresponds to SideEffectEntry in ADR-022.
  """
  @derive Jason.Encoder
  defstruct [
    :type,
    :name,
    :declared_on,
    :idempotency_key_from,
    :step_name,
    :action,
    :job_module,
    :module,
    :queue,
    :trigger,
    idempotent: false,
    declared: false,
    epistemic: "VERIFIED"
  ]
end

defmodule Foundry.SparkMeta.StepFacts do
  @moduledoc false

  defstruct [
    read_targets: [],
    write_targets: [],
    rules_applied: [],
    policy_checks: [],
    queue_targets: [],
    external_calls: [],
    output_resources: %{},
    direct_result_resources: [],
    variable_resources: %{},
    helper_results: %{},
    provenance: %{
      reads: %{},
      writes: %{},
      rules: %{},
      policies: %{},
      queues: %{},
      external_calls: %{}
    }
  ]
end

defmodule Foundry.SparkMeta.SourceContext do
  @moduledoc false

  defstruct [
    :module,
    :source_text,
    :module_source,
    alias_map: %{},
    step_sources: %{},
    helper_sources: %{}
  ]
end

defmodule Foundry.SparkMeta.MoneyAttr do
  @moduledoc "Structured representation of a monetary attribute."
  @derive Jason.Encoder
  defstruct [:name, :type, :cldr_backend]

end

defmodule Foundry.SparkMeta.Relationship do
  @moduledoc "Structured representation of an Ash resource relationship."
  @derive Jason.Encoder
  defstruct [:name, :type, :related_resource, :source_attribute, :destination_attribute, :description]

end

defmodule Foundry.SparkMeta.AuthStrategy do
  @moduledoc "Structured representation of an AshAuthentication strategy."
  @derive Jason.Encoder
  defstruct [:strategy_name, :strategy_type, :identity_field, :token_resource, :has_sign_in_tokens, :has_password_reset]

end

defmodule Foundry.SparkMeta do
  @moduledoc """
  Foundry-specific Spark DSL walker for introspecting compiled modules.

  Produces ModuleInfo structs with Foundry-specific field extensions beyond the generic
  SparkMeta.DslState, including type detection, state machines, Oban configuration,
  and runbook extraction.

  The walker uses a pipeline pattern: start with a basic ModuleInfo struct,
  then apply a series of transformations to populate fields via Spark introspection APIs.

  Entry point: `walk(module)` returns %ModuleInfo{} or a graceful fallback
  struct with nil/[] defaults.
  """

  alias Foundry.SparkMeta.{ModuleInfo, SourceContext, StepFacts}

  @spec walk(module :: module()) :: ModuleInfo.t()
  def walk(module) when is_atom(module) do
    %ModuleInfo{module: module}
    |> put_description()
    |> put_type()
    # @telemetry_prefix, @runbook, @compliance, @adrs
    |> put_module_attributes()
    # attributes, actions, data_layer
    |> put_ash_resource_fields()
    # relationships
    |> put_relationships()
    # paper_trail, archival, auth_subject
    |> put_extension_fields()
    # AshStateMachine entities
    |> put_state_machine()
    # AshAuthentication strategies
    |> put_auth_strategies()
    # scan attributes for Ash.Type.Money
    |> put_money_attributes()
    # AshJsonApi entities
    |> put_api_routes()
    # Spark DSL entities if Reactor
    |> put_reactor_steps()
    # behaviour list
    |> put_oban_fields()
    # @performs attribute for Oban workers
    |> put_oban_performs()
    # AshAI DSL entities if present
    |> put_agent_steps()
    # extract side effects from annotations and DSL
    |> put_side_effects()
    # source file mtime
    |> put_last_modified()
  rescue
    # graceful fallback for non-Spark modules
    _ -> %ModuleInfo{module: module}
  end

  # ---- Pipeline transformation functions ----

  defp put_description(%ModuleInfo{module: module} = info) do
    description =
      # First try: moduledoc attribute (from @moduledoc)
      case module.__info__(:attributes)[:moduledoc] do
        [{_line, doc}] when is_binary(doc) ->
          # For rule modules, keep the full text so "Applied by:" can be parsed
          # For other modules, keep just the first paragraph
          if rule_module?(module) do
            String.trim(doc)
          else
            doc
            |> String.split("\n\n")
            |> Enum.reject(&(String.trim(&1) == ""))
            |> List.first()
            |> then(&if &1, do: String.trim(&1), else: nil)
          end

        _ ->
          # Fallback: try calling description/0 callback (e.g., for rules)
          try do
            if function_exported?(module, :description, 0) do
              module.description()
            else
              nil
            end
          rescue
            _ -> nil
          end
      end

    %{info | description: description}
  rescue
    _ -> info
  end

  defp put_type(%ModuleInfo{module: module} = info) do
    type =
      cond do
        reactor_module?(module) and transfer_module?(module) -> :transfer
        reactor_module?(module) -> :reactor
        oban_worker?(module) -> :job
        trigger_module?(module) -> :trigger
        blueprint_module?(module) -> :blueprint
        provider_module?(module) -> :provider
        liveview_module?(module) -> :liveview
        liveresource_module?(module) -> :liveresource
        agent_module?(module) -> :agent
        rule_module?(module) -> :rule
        ash_resource?(module) -> :resource
        true -> :resource
      end

    trigger_kind =
      case type do
        :trigger -> detect_trigger_kind(module)
        _ -> nil
      end

    %{info | type: type, trigger_kind: trigger_kind}
  rescue
    _ -> info
  end

  defp put_module_attributes(%ModuleInfo{module: module} = info) do
    attrs = module.__info__(:attributes)

    runbook = get_attr_single(attrs, :runbook)
    # Fallback: for Reactor modules, __info__(:attributes) may not have @runbook
    # Try to extract it from the source file directly
    runbook = runbook || extract_runbook_from_source(module)

    trigger_kind = get_attr_single(attrs, :trigger_kind) || info.trigger_kind

    %{
      info
      | telemetry_prefix: get_attr_list(attrs, :telemetry_prefix),
        runbook: runbook,
        compliance: get_attr_list(attrs, :compliance),
        adrs: get_attr_list(attrs, :adrs),
        trigger_kind: trigger_kind
    }
  rescue
    _ -> info
  end

  defp put_ash_resource_fields(%ModuleInfo{module: module} = info) do
    if ash_resource?(module) do
      attributes =
        try do
          Ash.Resource.Info.attributes(module)
          |> Enum.map(&attribute_to_struct/1)
        rescue
          _ -> []
        end

      actions =
        try do
          Ash.Resource.Info.actions(module)
          |> Enum.map(&action_to_struct/1)
        rescue
          _ -> []
        end

      data_layer =
        try do
          Ash.Resource.Info.data_layer(module)
          |> then(&if &1, do: to_string(&1), else: nil)
        rescue
          _ -> nil
        end

      %{info | attributes: attributes, actions: actions, data_layer: data_layer}
    else
      info
    end
  rescue
    _ -> info
  end

  defp put_relationships(%ModuleInfo{module: module} = info) do
    if ash_resource?(module) do
      relationships =
        try do
          Ash.Resource.Info.relationships(module)
          # Filter out private system relationships like paper_trail_versions
          |> Enum.filter(fn rel ->
            rel.public? || (rel.name && !String.starts_with?(to_string(rel.name), "paper_trail"))
          end)
          |> Enum.map(&relationship_to_struct/1)
        rescue
          _ -> []
        end

      %{info | relationships: relationships}
    else
      info
    end
  rescue
    _ -> info
  end

  defp put_extension_fields(%ModuleInfo{module: module} = info) do
    extensions = safe_extensions(module)

    %{
      info
      | paper_trail: AshPaperTrail.Resource in extensions,
        archival: AshArchival.Resource in extensions,
        authentication_subject: Enum.any?(extensions, &authentication_ext?/1),
        rate_limited: Enum.any?(extensions, &rate_limit_ext?/1)
    }
  rescue
    _ -> info
  end

  defp put_state_machine(%ModuleInfo{module: module} = info) do
    if AshStateMachine.Resource in safe_extensions(module) do
      states =
        try do
          SparkMeta.entities(module, [:state_machine, :states])
          |> Enum.map(&to_string(&1.name))
        rescue
          _ -> []
        end

      transitions =
        try do
          SparkMeta.entities(module, [:state_machine, :transitions])
          |> Enum.map(fn t ->
            %{from: to_string(t.from), to: to_string(t.to), action: to_string(t.action)}
          end)
        rescue
          _ -> []
        end

      state_attr =
        try do
          SparkMeta.get_opt(module, [:state_machine], :state_attribute, nil)
          |> then(&if &1, do: to_string(&1), else: nil)
        rescue
          _ -> nil
        end

      initial_states =
        try do
          SparkMeta.get_opt(module, [:state_machine], :initial_states, [])
          |> Enum.map(&to_string/1)
        rescue
          _ -> []
        end

      default_initial_state =
        try do
          SparkMeta.get_opt(module, [:state_machine], :default_initial_state, nil)
          |> then(&if &1, do: to_string(&1), else: nil)
        rescue
          _ -> nil
        end

      terminal_states = compute_terminal_states(states, transitions)

      %{
        info
        | state_machine: %{
            present: true,
            states: states,
            transitions: transitions,
            state_attribute: state_attr,
            initial_states: initial_states,
            default_initial_state: default_initial_state,
            terminal_states: terminal_states
          }
      }
    else
      info
    end
  rescue
    _ -> info
  end

  defp compute_terminal_states(states, transitions) do
    from_states = transitions |> Enum.map(& &1["from"]) |> MapSet.new()
    states |> Enum.filter(&(&1 not in from_states))
  end

  defp put_auth_strategies(%ModuleInfo{module: module} = info) do
    has_auth =
      try do
        AshAuthentication in safe_extensions(module)
      rescue
        _ -> false
      end

    if has_auth do
      # Get the global token resource configured for this authentication extension
      # Currently extracted from auth_strategies; global token_resource will be handled in Phase D
      global_token_resource = nil

      strategies =
        try do
          SparkMeta.entities(module, [:authentication, :strategies])
          |> Enum.map(&auth_strategy_to_struct(&1, global_token_resource))
        rescue
          _ -> []
        end

      %{info | auth_strategies: strategies}
    else
      info
    end
  rescue
    _ -> info
  end

  defp put_money_attributes(%ModuleInfo{attributes: attributes} = info) do
    money_attrs =
      attributes
      |> Enum.filter(&(&1.type == "Ash.Type.Money"))
      |> Enum.map(
        &%Foundry.SparkMeta.MoneyAttr{
          name: &1.name,
          type: &1.type,
          cldr_backend: &1.cldr_backend
        }
      )

    %{info | money_attributes: money_attrs}
  rescue
    _ -> info
  end

  defp put_api_routes(%ModuleInfo{module: module} = info) do
    # AshJsonApi.Resource presence indicates API routes, but details are Phase 2+
    has_json_api =
      try do
        AshJsonApi.Resource in safe_extensions(module)
      rescue
        _ -> false
      end

    if has_json_api do
      # For now, mark as present but details deferred
      %{info | api_routes: []}
    else
      info
    end
  rescue
    _ -> info
  end

  defp put_reactor_steps(%ModuleInfo{module: module} = info) do
    # Reactor modules export entities/1 function to access DSL entities
    if function_exported?(module, :entities, 1) do
      source_context = module_source_context(module)
      declared_side_effects = declared_step_side_effects(module)

      raw_steps =
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
              format_module_fqn(Map.get(step, :resource))

          step_entry = %Foundry.SparkMeta.StepEntry{
            name: step.name,
            type:
              Map.get(step, :type)
              |> then(
                &if &1,
                  do: to_string(&1),
                  else: step.__struct__ |> Module.split() |> List.last() |> String.downcase()
              ),
            description: Map.get(step, :description),
            target_module: Map.get(step, :impl) || Map.get(step, :resource),
            step_index: index,
            wait_for: Map.get(step, :wait_for, []) |> Enum.map(&to_string/1),
            has_compensation:
              Map.get(step, :compensate) != nil || Map.get(step, :undo_action) != nil,
            target_resource: target_resource,
            target_action: target_action,
            step_kind: derive_step_kind(step, facts),
            rules_applied: facts.rules_applied,
            source_snippet: snippet,
            read_targets: facts.read_targets,
            write_targets: facts.write_targets,
            fact_provenance: facts.provenance,
            side_effects:
              declared_step_side_effects_for(step.name, declared_side_effects) ++
                extract_side_effects_from_step(snippet, step.name)
                |> Enum.uniq()
          }

          next_outputs =
            Map.put(step_outputs, to_string(step.name), %{
              keys: facts.output_resources,
              direct: facts.direct_result_resources
            })

          {step_entry, next_outputs}
        end)

      %{info | steps: steps}
    else
      info
    end
  rescue
    _ -> info
  end

  defp derive_step_kind(step, %StepFacts{} = facts) do
    cond do
      facts.write_targets != [] -> :write
      facts.read_targets != [] -> :read
      true -> derive_step_kind(step)
    end
  end

  defp derive_step_kind(step) do
    struct_name = step.__struct__ |> Module.split() |> List.last()
    case struct_name do
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

  defp format_module_fqn(nil), do: nil

  defp format_module_fqn(module) when is_atom(module) do
    module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp format_module_fqn(module) when is_binary(module), do: module
  defp format_module_fqn(_), do: nil

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

  defp module_source_context(module) do
    with path when is_binary(path) <- module_source_path(module),
         {:ok, source_text} <- File.read(path),
         {:ok, module_context} <- extract_module_context(source_text, module) do
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

  defp extract_module_context(source_text, module) do
    with {:ok, ast} <- Code.string_to_quoted(source_text),
         modules when is_list(modules) <- collect_module_definitions(ast, length(String.split(source_text, "\n"))),
         module_name <- format_module_fqn(module),
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
    |> Enum.reject(fn {name, _line} -> is_nil(name) end)
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
      [_, arg_name, step_name, key] ->
        {arg_name, %{step: step_name, key: blank_to_nil(key)}}

      [_, arg_name, step_name] ->
        {arg_name, %{step: step_name, key: nil}}
    end)
  end

  defp build_variable_resource_map(nil, _alias_map, _step_outputs, _arg_provenance, _helper_results),
    do: %{}

  defp build_variable_resource_map(
         snippet,
         alias_map,
         step_outputs,
         arg_provenance,
         helper_results
       ) do
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

    from_args =
      arg_shapes
      |> Enum.map(fn {arg_name, %{direct: resources}} -> {arg_name, resources} end)

    from_fn_params =
      extract_fn_param_bindings(snippet, arg_shapes)

    from_ash =
      extract_variable_bindings(snippet, alias_map)

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
    read_targets =
      extract_resource_refs(snippet, ~r/Ash\.(?:get|read)\(\s*([^,\s)]+)/, alias_map)

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
      helper_variable_resources =
        build_variable_resource_map(helper_source, source_context.alias_map, %{}, %{}, %{})

      helper_results =
        infer_direct_result_resources(
          helper_source,
          helper_variable_resources,
          direct.read_targets,
          direct.write_targets
        )

      %StepFacts{
        read_targets: Enum.uniq(acc.read_targets ++ direct.read_targets ++ nested.read_targets),
        write_targets:
          Enum.uniq(acc.write_targets ++ direct.write_targets ++ nested.write_targets),
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
        helper_variable_resources =
          build_variable_resource_map(helper_source, source_context.alias_map, %{}, %{}, %{})

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
        %{keys: keys} ->
          Enum.flat_map(updated_variables, &Map.get(keys, &1, []))

        _ ->
          []
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
    |> Enum.map(fn se ->
      %Foundry.SparkMeta.SideEffectEntry{
        type: se.type,
        name: to_string(se[:name] || ""),
        declared: true,
        declared_on: :module_attribute,
        idempotent: se[:idempotent],
        idempotency_key_from: normalize_step_side_effect_key(se[:idempotency_key_from] || se[:key_from]),
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
  defp module_name(module) when is_atom(module), do: format_module_fqn(module)
  defp module_name(_), do: nil

  defp extract_named_atom(args) when is_list(args) do
    Enum.find_value(args, fn
      atom when is_atom(atom) -> atom
      _ -> nil
    end)
  end

  defp extract_named_atom(_), do: nil

  defp extract_function_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp extract_function_name(_), do: nil

  defp count_resource_targets(read_targets, write_targets) do
    (read_targets ++ write_targets) |> Enum.uniq() |> length()
  end

  defp normalize_step_side_effect_key(nil), do: []

  defp normalize_step_side_effect_key(list) when is_list(list) do
    Enum.map(list, &to_string/1)
  end

  defp normalize_step_side_effect_key(key) do
    [to_string(key)]
  end

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
                {:->, _, [[pattern | _], _body]} ->
                  bind_param_pattern(pattern, arg_shapes)

                _ ->
                  []
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
          {:ok, {:%{}, _, fields}} = node, acc ->
            {node, [fields | acc]}

          node, acc ->
            {node, acc}
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

  defp put_oban_fields(%ModuleInfo{module: module} = info) do
    behaviours =
      try do
        module.__info__(:attributes) |> Keyword.get(:behaviour, [])
      rescue
        _ -> []
      end

    if Oban.Worker in behaviours do
      # Extract queue names from Oban.Worker configuration
      # Oban.Worker is NOT a Spark DSL module; queue is in use Oban.Worker, queue: :default
      queues =
        try do
          opts = module.__oban_opts__()
          case Keyword.get(opts, :queue) do
            nil -> []
            q -> [to_string(q)]
          end
        rescue
          _ -> []
        end

      %{info | oban_queues: queues}
    else
      info
    end
  rescue
    _ -> info
  end

  defp put_oban_performs(%ModuleInfo{module: module} = info) do
    # Extract performs from @foundry config map for Oban workers
    # Usage: @foundry %{performs: ModuleName} or %{performs: "ModuleName"}
    behaviours =
      try do
        module.__info__(:attributes) |> Keyword.get(:behaviour, [])
      rescue
        _ -> []
      end

    if Oban.Worker in behaviours do
      performs =
        try do
          attrs = module.__info__(:attributes)
          # Check direct @performs attribute (Foundry.Annotations registered)
          direct = get_attr_raw(attrs, :performs)
          # Fallback: @foundry %{performs: ...} map
          from_foundry =
            with cfg when is_map(cfg) <- get_attr_raw(attrs, :foundry),
                 val when not is_nil(val) <- Map.get(cfg, :performs),
                 do: val,
                 else: (_ -> nil)

          case direct || from_foundry do
            a when is_atom(a) and not is_nil(a) ->
              a |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
            s when is_binary(s) -> s
            _ -> nil
          end
        rescue
          _ -> nil
        end

      %{info | performs: performs}
    else
      info
    end
  rescue
    _ -> info
  end

  defp put_agent_steps(%ModuleInfo{module: module} = info) do
    # AshAI agent steps detection and extraction deferred to Phase 2+
    # For now, always empty list
    has_ash_ai =
      try do
        function_exported?(module, :__ash_ai__, 0)
      rescue
        _ -> false
      end

    if has_ash_ai do
      %{info | agent_steps: []}
    else
      info
    end
  rescue
    _ -> info
  end

  defp put_side_effects(%ModuleInfo{module: module} = info) do
    side_effects =
      cond do
        ash_resource?(module) ->
          extract_action_side_effects(module)

        info.type in [:reactor, :transfer] ->
          info.steps
          |> Enum.flat_map(& &1.side_effects)
          |> Enum.uniq()

        info.type == :trigger ->
          module_source_context(module)
          |> then(&extract_module_side_effects(&1.module_source, info.trigger_kind))

        true ->
          []
      end

    %{info | side_effects: side_effects}
  rescue
    _ -> info
  end

  defp extract_action_side_effects(module) do
    try do
      Ash.Resource.Info.actions(module)
      |> Enum.flat_map(fn action ->
        notifiers = Map.get(action, :notifiers, [])
        changes = Map.get(action, :changes, [])

        entries = []

        entries =
          entries ++
            Enum.map(notifiers, fn n ->
              %Foundry.SparkMeta.SideEffectEntry{
                type: :ash_notifier,
                name: format_module_fqn(n),
                declared_on: :resource_action,
                action: to_string(action.name),
                declared: true,
                epistemic: "VERIFIED"
              }
            end)

        entries ++
          Enum.filter(changes, fn
            %{change: {change_mod, _opts}} -> trigger_change?(change_mod)
            %{change: change_mod} -> trigger_change?(change_mod)
            _ -> false
          end)
          |> Enum.map(fn
            %{change: {change_mod, _opts}} -> change_mod
            %{change: change_mod} -> change_mod
          end)
          |> Enum.map(fn mod ->
            %Foundry.SparkMeta.SideEffectEntry{
              type: :ash_change,
              name: format_module_fqn(mod),
              declared_on: :resource_action,
              action: to_string(action.name),
              declared: true,
              epistemic: "VERIFIED"
            }
          end)
      end)
    rescue
      _ -> []
    end
  end

  defp trigger_change?(module) do
    # Heuristic: changes in a .Changes or .Notifiers namespace likely have side effects
    mod_str = to_string(module)
    String.contains?(mod_str, [".Changes.", ".Notifiers."])
  end

  defp extract_side_effects_from_step(nil, _step_name), do: []

  defp extract_side_effects_from_step(snippet, step_name) do
    # 1. Parse @side_effect annotations
    # Format: # @side_effect type: name, key: value
    annotated =
      Regex.scan(~r/#\s*@side_effect\s+([^:\n]+):\s*([^,\n]+)(.*)/, snippet)
      |> Enum.map(fn [_, type_str, name_str, rest] ->
        opts = parse_side_effect_opts(rest)
        %Foundry.SparkMeta.SideEffectEntry{
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

    # 2. Heuristics for undeclared side effects
    inferred = []

    inferred = if String.contains?(snippet, ["Oban.insert", "Oban.insert!"]) and not has_side_effect_type?(annotated, :oban_emit) do
      oban_job_name =
        case Regex.run(~r/Oban\.insert[!]?\(\s*([A-Z][A-Za-z0-9.]+)\.new/, snippet) do
          [_, mod] -> mod
          _ -> "unnamed_oban_job"
        end

      inferred ++ [%Foundry.SparkMeta.SideEffectEntry{
        type: :oban_emit,
        name: oban_job_name,
        declared_on: :step,
        step_name: to_string(step_name),
        declared: false,
        epistemic: "INFERRED"
      }]
    else
      inferred
    end

    inferred = if String.contains?(snippet, ["Req.", "Finch.", "HTTPoison", "Tesla"]) and not has_side_effect_type?(annotated, :external_http) do
      inferred ++ [%Foundry.SparkMeta.SideEffectEntry{
        type: :external_http,
        name: "external_call",
        declared_on: :step,
        step_name: to_string(step_name),
        declared: false,
        epistemic: "INFERRED"
      }]
    else
      inferred
    end

    annotated ++ inferred
  end

  defp has_side_effect_type?(entries, type) do
    Enum.any?(entries, &(&1.type == type))
  end

  defp extract_module_side_effects(nil, _trigger_kind), do: []

  defp extract_module_side_effects(module_source, trigger_kind) do
    Regex.scan(~r/#\s*@side_effect\s+([^:\n]+):\s*([^,\n]+)(.*)/, module_source)
    |> Enum.map(fn [_, type_str, name_str, rest] ->
      opts = parse_side_effect_opts(rest)

      %Foundry.SparkMeta.SideEffectEntry{
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
    |> Enum.into(%{}, fn [_, k, v] -> {k, v} end)
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

  defp put_last_modified(%ModuleInfo{module: module} = info) do
    last_modified =
      try do
        module |> :code.which() |> to_string() |> File.stat!() |> then(& &1.mtime)
      rescue
        _ -> nil
      end

    %{info | last_modified: last_modified}
  rescue
    _ -> info
  end

  # ---- Helper functions for type detection ----

  defp ash_resource?(module) do
    try do
      # Try multiple ways to detect Ash resources
      # Ash 3.x: __ash_resource__/0 function
      function_exported?(module, :__ash_resource__, 0) ||
        # Fallback: __ash_resource__/0 function exists (Ash 2.x style)
        (try do
          module.__ash_resource__()
          true
        rescue
          _ -> false
        end) ||
        # Fallback: Check if Ash.Resource.Info functions work
        (try do
          _ = Ash.Resource.Info.relationships(module)
          true
        rescue
          _ -> false
        end)
    rescue
      _ -> false
    end
  end

  defp reactor_module?(module) do
    # Reactor modules export either __reactor__ or reactor/0
    function_exported?(module, :__reactor__, 0) or function_exported?(module, :reactor, 0)
  rescue
    _ -> false
  end

  defp transfer_module?(module) do
    try do
      AshDoubleEntry.Transfers.Transfer in safe_extensions(module)
    rescue
      _ -> false
    end
  end

  defp trigger_module?(module) do
    try do
      module_str = format_module_fqn(module)

      String.ends_with?(module_str || "", "Webhook") or
        function_exported?(module, :handle_webhook, 3)
    rescue
      _ -> false
    end
  end

  defp detect_trigger_kind(module) do
    try do
      module_str = format_module_fqn(module)

      cond do
        String.ends_with?(module_str || "", "Webhook") -> "webhook"
        function_exported?(module, :handle_webhook, 3) -> "webhook"
        true -> nil
      end
    rescue
      _ -> nil
    end
  end

  defp oban_worker?(module) do
    try do
      behaviours = module.__info__(:attributes) |> Keyword.get(:behaviour, [])
      Oban.Worker in behaviours
    rescue
      _ -> false
    end
  end

  defp rule_module?(module) do
    try do
      behaviours = module.__info__(:attributes) |> Keyword.get(:behaviour, [])

      # Check for standard Ash policy checks or custom rule behaviours
      Enum.any?(behaviours, fn behaviour ->
        behaviour in [Ash.Policy.Check, Ash.Policy.SimpleCheck] or
        (is_atom(behaviour) and String.ends_with?(Atom.to_string(behaviour), ".Rule"))
      end)
    rescue
      _ -> false
    end
  end

  defp blueprint_module?(module) do
    try do
      function_exported?(module, :__blueprint__, 0)
    rescue
      _ -> false
    end
  end

  defp provider_module?(module) do
    # Providers implement a behaviour or have specific module attributes
    try do
      behaviours = module.__info__(:attributes) |> Keyword.get(:behaviour, [])
      Enum.any?(behaviours, &module_has_behaviour?/1)
    rescue
      _ -> false
    end
  end

  defp liveview_module?(module) do
    try do
      behaviours = module.__info__(:attributes) |> Keyword.get(:behaviour, [])
      Phoenix.LiveView in behaviours
    rescue
      _ -> false
    end
  end

  defp liveresource_module?(module) do
    try do
      module_string = to_string(module)
      String.contains?(module_string, "Live")
    rescue
      _ -> false
    end
  end

  defp agent_module?(module) do
    # Agent detection via AshAI module attributes
    try do
      attrs = module.__info__(:attributes)
      Keyword.has_key?(attrs, :agent_type)
    rescue
      _ -> false
    end
  end

  defp module_has_behaviour?(behaviour) when is_atom(behaviour) do
    # Recognize common provider behaviour patterns
    behaviour_str = to_string(behaviour)
    String.contains?(behaviour_str, ["ProviderAdapter", "Provider"])
  end

  defp module_has_behaviour?(_behaviour) do
    false
  end

  defp safe_extensions(module) do
    SparkMeta.extensions(module)
  rescue
    _ -> []
  end

  # ---- Attribute conversion helpers ----

  defp attribute_to_struct(%Ash.Resource.Attribute{} = attr) do
    %Foundry.SparkMeta.Attribute{
      name: attr.name,
      type: attr.type |> format_type(),
      description: attr.description,
      pii: false,
      sensitive: attr.sensitive? || false,
      money: attr.type == Ash.Type.Money,
      cldr_backend: extract_cldr_backend(attr)
    }
  rescue
    _ ->
      %Foundry.SparkMeta.Attribute{
        name: attr.name,
        type: "unknown"
      }
  end

  defp action_to_struct(%{name: name, type: type, description: description}) do
    %Foundry.SparkMeta.Action{
      name: name,
      type: type,
      description: description
    }
  rescue
    _ ->
      %Foundry.SparkMeta.Action{
        name: :unknown,
        type: :unknown
      }
  end

  defp relationship_to_struct(rel) when is_map(rel) do
    try do
      dest_atom = Map.get(rel, :destination)
      related_resource =
        case dest_atom do
          a when is_atom(a) ->
            a
            |> Atom.to_string()
            |> String.replace_prefix("Elixir.", "")
          s when is_binary(s) -> s
          _ -> "unknown"
        end

      %Foundry.SparkMeta.Relationship{
        name: to_string(Map.get(rel, :name)),
        type: Map.get(rel, :type),
        related_resource: related_resource,
        source_attribute: Map.get(rel, :source_attribute) |> then(&if &1, do: to_string(&1), else: nil),
        destination_attribute: Map.get(rel, :destination_attribute) |> then(&if &1, do: to_string(&1), else: nil),
        description: Map.get(rel, :description)
      }
    rescue
      _ ->
        %Foundry.SparkMeta.Relationship{
          name: "unknown",
          type: :unknown,
          related_resource: "unknown"
        }
    end
  end

  defp relationship_to_struct(_) do
    %Foundry.SparkMeta.Relationship{
      name: "unknown",
      type: :unknown,
      related_resource: "unknown"
    }
  end

  defp auth_strategy_to_struct(strategy, global_token_resource) do
    # Extract strategy type from struct name (e.g., AshAuthentication.Strategy.Password → :password)
    strategy_type =
      try do
        strategy.__struct__
        |> Module.split()
        |> List.last()
        |> String.downcase()
        |> String.to_atom()
      rescue
        _ -> :other
      end

    # Extract identity field
    identity_field =
      try do
        Map.get(strategy, :identity_field) |> then(&if &1, do: to_string(&1), else: nil)
      rescue
        _ -> nil
      end

    # Extract token resource FQN - prefer strategy-level, fallback to global
    token_resource =
      try do
        strategy_token = Map.get(strategy, :token_resource)
        if strategy_token do
          strategy_token |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
        else
          global_token_resource
        end
      rescue
        _ -> global_token_resource
      end

    # Check for sign_in_tokens and password_reset options
    has_sign_in_tokens =
      try do
        token_opts = Map.get(strategy, :sign_in_tokens_enabled)
        token_opts == true
      rescue
        _ -> false
      end

    has_password_reset =
      try do
        Map.get(strategy, :password_reset_enabled) == true
      rescue
        _ -> false
      end

    %Foundry.SparkMeta.AuthStrategy{
      strategy_name: to_string(Map.get(strategy, :name, :unknown)),
      strategy_type: strategy_type,
      identity_field: identity_field,
      token_resource: token_resource,
      has_sign_in_tokens: has_sign_in_tokens,
      has_password_reset: has_password_reset
    }
  rescue
    _ ->
      %Foundry.SparkMeta.AuthStrategy{
        strategy_name: "unknown",
        strategy_type: :other,
        identity_field: nil,
        token_resource: nil,
        has_sign_in_tokens: false,
        has_password_reset: false
      }
  end

  defp format_type(type) when is_atom(type) do
    type |> to_string()
  rescue
    _ -> "unknown"
  end

  defp format_type(type) when is_binary(type) do
    type
  rescue
    _ -> "unknown"
  end

  defp format_type(_), do: "unknown"

  defp extract_cldr_backend(%Ash.Resource.Attribute{type: Ash.Type.Money} = attr) do
    # Extract CLDR backend from Money type constraints if present
    try do
      constraints = attr.constraints || []
      Keyword.get(constraints, :cldr_backend)
    rescue
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp extract_cldr_backend(_), do: nil

  # ---- Attribute helpers ----

  defp get_attr_list(attrs, key) do
    case Keyword.get(attrs, key) do
      nil -> []
      list when is_list(list) -> Enum.map(list, &to_string/1)
      value -> [to_string(value)]
    end
  rescue
    _ -> []
  end

  defp get_attr_raw(attrs, key) do
    case Keyword.get(attrs, key) do
      nil -> nil
      [value | _] -> value
      value -> value
    end
  rescue
    _ -> nil
  end

  defp get_attr_single(attrs, key) do
    case Keyword.get(attrs, key) do
      nil -> nil
      [value | _] -> to_string(value)
      value -> to_string(value)
    end
  rescue
    _ -> nil
  end

  # Fallback to extract @runbook from source file for modules (like Reactor)
  # where __info__(:attributes) doesn't preserve the attribute
  defp extract_runbook_from_source(module) do
    try do
      module_str = Atom.to_string(module)
      # Look for the source file by searching in lib/
      case module_source_path(module) do
        nil -> nil
        file -> extract_runbook_from_file(file, module_str)
      end
    rescue
      _ -> nil
    end
  end

  defp module_source_path(module) when is_atom(module) do
    try do
      case module.__info__(:compile)[:source] do
        nil -> find_module_source_file(Atom.to_string(module))
        charlist ->
          path = to_string(charlist)
          if File.exists?(path), do: path, else: find_module_source_file(Atom.to_string(module))
      end
    rescue
      _ -> find_module_source_file(Atom.to_string(module))
    end
  end

  # Search for the module's source file in lib/ directories
  defp find_module_source_file(module_str) do
    # Convert Module.Name to module/name.ex (with underscoring applied)
    # Module format: "Elixir.ProjectName.Section.Module"
    # File path: lib/section/module.ex (project name prefix is omitted)
    parts = String.split(module_str, ".")
    # Drop "Elixir" and project name (first two parts)
    filename_lower =
      (parts
       |> Enum.drop(2)
       |> Enum.map(&Macro.underscore/1)
       |> Enum.join("/")) <> ".ex"

    cwd = File.cwd!()

    # Try standard patterns first
    candidates = [
      Path.join(cwd, "lib/#{filename_lower}"),
      Path.join(cwd, filename_lower)
    ]

    case Enum.find(candidates, &File.exists?/1) do
      nil ->
        # Fallback: search lib/*.ex files for the module definition (for multi-module files)
        search_lib_files(Path.join(cwd, "lib"), module_str)
      file ->
        file
    end
  end

  # Search .ex files in lib and subdirectories for module definition
  defp search_lib_files(lib_path, module_str) do
    try do
      # Strip "Elixir." prefix if present (Atom.to_string includes it)
      clean_module_str = String.replace_prefix(module_str, "Elixir.", "")

      lib_path
      |> File.ls!()
      |> Enum.find_value(fn entry ->
        full_path = Path.join(lib_path, entry)
        cond do
          File.dir?(full_path) ->
            # Recurse into subdirectory
            search_lib_files(full_path, module_str)

          String.ends_with?(entry, ".ex") ->
            case File.read(full_path) do
              {:ok, content} ->
                if String.contains?(content, "defmodule #{clean_module_str}") do
                  full_path
                else
                  nil
                end

              _ ->
                nil
            end

          true ->
            nil
        end
      end)
    rescue
      _ -> nil
    end
  end

  # Extract @runbook value for a specific module from source file
  # Handles multiple module definitions in one file by finding the module's defmodule block
  defp extract_runbook_from_file(file, module_str) do
    try do
      # Strip "Elixir." prefix if present
      clean_module_str = String.replace_prefix(module_str, "Elixir.", "")

      content = File.read!(file)
      lines = String.split(content, "\n")

      # Find the line where this module is defined
      module_line_idx =
        lines
        |> Enum.find_index(fn line ->
          String.contains?(line, "defmodule #{clean_module_str}")
        end)

      case module_line_idx do
        nil ->
          nil

        idx ->
          # Extract only the lines for this module's block (until the next defmodule)
          rest = Enum.drop(lines, idx + 1)

          module_lines =
            Enum.take_while(rest, fn line ->
              not String.match?(line, ~r/^\s*defmodule\s+\w/)
            end)

          # Search for @runbook within the module's lines
          Enum.find_value(module_lines, fn line ->
            case Regex.run(~r/@runbook\s+"([^"]+)"/, line) do
              [_, path] -> path
              _ -> nil
            end
          end)
      end
    rescue
      _ -> nil
    end
  end

  defp authentication_ext?(ext) do
    ext in [AshAuthentication, AshAuthentication.Resource]
  rescue
    _ -> false
  end

  defp rate_limit_ext?(_ext) do
    # Extend when rate limiting DSL is added
    false
  rescue
    _ -> false
  end
end
