defmodule Foundry.SparkMeta.ModuleInfo do
  @moduledoc """
  Output struct from SparkMeta.walk/1.

  Mirrors the NodeEntry schema fields that SparkMeta can derive without Foundry-specific context.
  Fields like :sensitive (which requires manifest access) are absent — those are added by NodeBuilder.
  """

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
    auth_strategies: []
  ]
end

defmodule Foundry.SparkMeta.Attribute do
  @moduledoc "Structured representation of an Ash resource attribute."
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

defimpl Jason.Encoder, for: Foundry.SparkMeta.Attribute do
  def encode(entry, opts) do
    entry
    |> Map.from_struct()
    |> Foundry.Context.Compact.compact()
    |> Jason.Encode.map(opts)
  end
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
    # ash_ai v0.6 agent step fields (INV-014..017)
    step_model: nil,
    confidence_threshold: nil,
    on_low_confidence: nil,
    step_tools: [],
    step_telemetry_prefix: []
  ]
end

defimpl Jason.Encoder, for: Foundry.SparkMeta.StepEntry do
  def encode(entry, opts) do
    entry
    |> Map.from_struct()
    |> Foundry.Context.Compact.compact()
    |> Jason.Encode.map(opts)
  end
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

  alias Foundry.SparkMeta.ModuleInfo

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
        blueprint_module?(module) -> :blueprint
        provider_module?(module) -> :provider
        liveview_module?(module) -> :liveview
        liveresource_module?(module) -> :liveresource
        agent_module?(module) -> :agent
        rule_module?(module) -> :rule
        ash_resource?(module) -> :resource
        true -> :resource
      end

    %{info | type: type}
  rescue
    _ -> info
  end

  defp put_module_attributes(%ModuleInfo{module: module} = info) do
    attrs = module.__info__(:attributes)

    runbook = get_attr_single(attrs, :runbook)
    # Fallback: for Reactor modules, __info__(:attributes) may not have @runbook
    # Try to extract it from the source file directly
    runbook = runbook || extract_runbook_from_source(module)

    %{
      info
      | telemetry_prefix: get_attr_list(attrs, :telemetry_prefix),
        runbook: runbook,
        compliance: get_attr_list(attrs, :compliance),
        adrs: get_attr_list(attrs, :adrs)
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
      steps =
        try do
          module.entities([:reactor])
          |> Enum.filter(fn step ->
            struct_str = step.__struct__ |> Atom.to_string()
            is_struct(step) and (
              String.starts_with?(struct_str, "Elixir.Reactor.Dsl.Step") or
              String.starts_with?(struct_str, "Elixir.Ash.Reactor.Dsl")
            )
          end)
          |> Enum.with_index()
          |> Enum.map(fn {step, index} ->
            step_kind = derive_step_kind(step)
            target_resource = Map.get(step, :resource) || infer_target_resource_from_source(module, step)
            target_action = Map.get(step, :action) |> then(&if &1, do: to_string(&1), else: nil)

            rules_applied = extract_rules_from_step(module, step)

            %Foundry.SparkMeta.StepEntry{
              name: to_string(step.name),
              type:
                step.__struct__
                |> Module.split()
                |> List.last()
                |> String.downcase(),
              description: Map.get(step, :description),
              target_module: Map.get(step, :impl) || Map.get(step, :resource),
              step_index: index,
              wait_for: Map.get(step, :wait_for, []) |> Enum.map(&to_string/1),
              has_compensation: Map.get(step, :compensate) != nil,
              target_resource: format_module_fqn(target_resource),
              target_action: target_action,
              step_kind: step_kind,
              rules_applied: rules_applied
            }
          end)
        rescue
          _ -> []
        end

      %{info | steps: steps}
    else
      info
    end
  rescue
    _ -> info
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

  defp infer_target_resource_from_source(module, step) do
    # Heuristic: scan source file for Ash.create, Ash.update, Ash.get patterns
    try do
      case find_module_source_file(Atom.to_string(module)) do
        nil -> nil
        file -> extract_target_resource_from_step(file, to_string(step.name))
      end
    rescue
      _ -> nil
    end
  end

  defp extract_target_resource_from_step(file, step_name) do
    try do
      content = File.read!(file)
      # Find step block by name, then scan only that block for Ash calls
      step_pattern = ~r/step\s+:#{Regex.escape(step_name)}\b/
      case Regex.run(step_pattern, content, return: :index) do
        [{start, _}] ->
          # Extract from step start to next top-level step or end
          remaining = String.slice(content, start, String.length(content) - start)
          extract_ash_resource_ref(remaining)
        _ ->
          # Fallback: scan entire file if step name not found
          extract_ash_resource_ref(content)
      end
    rescue
      _ -> nil
    end
  end

  defp extract_ash_resource_ref(content) do
    patterns = [
      ~r/Ash\.create\(([A-Z][A-Za-z0-9.]*)/,
      ~r/Ash\.update\([^,]+,\s*([A-Z][A-Za-z0-9.]*)/,
      ~r/Ash\.get\(([A-Z][A-Za-z0-9.]*)/,
      ~r/Ash\.read\(([A-Z][A-Za-z0-9.]*)/,
      ~r/Ash\.destroy\(([A-Z][A-Za-z0-9.]*)/
    ]
    Enum.find_value(patterns, fn pat ->
      case Regex.run(pat, content) do
        [_, resource] -> resource
        _ -> nil
      end
    end)
  end

  defp extract_rules_from_step(module, step) do
    try do
      case find_module_source_file(Atom.to_string(module)) do
        nil -> []
        file -> extract_rule_refs_from_step(file, to_string(step.name))
      end
    rescue
      _ -> []
    end
  end

  defp extract_rule_refs_from_step(file, step_name) do
    try do
      content = File.read!(file)
      # Find step block by name, then scan that block for Rules.X.evaluate calls
      step_pattern = ~r/step\s+:#{Regex.escape(step_name)}\b/
      case Regex.run(step_pattern, content, return: :index) do
        [{start, _}] ->
          # Extract from step start to next top-level step or end (scan ~800 chars)
          remaining = String.slice(content, start, min(String.length(content) - start, 800))
          find_rule_evaluations(remaining)
        _ ->
          # Fallback: scan entire file if step name not found
          find_rule_evaluations(content)
      end
    rescue
      _ -> []
    end
  end

  defp find_rule_evaluations(content) do
    # Pattern: SomeModule.Rules.RuleName.evaluate
    pattern = ~r/([A-Z][A-Za-z0-9._]*\.Rules\.[A-Z][A-Za-z0-9._]*)/
    Regex.scan(pattern, content)
    |> Enum.map(&List.first/1)
    |> Enum.uniq()
  end

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
      case find_module_source_file(module_str) do
        nil -> nil
        file -> extract_runbook_from_file(file, module_str)
      end
    rescue
      _ -> nil
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
