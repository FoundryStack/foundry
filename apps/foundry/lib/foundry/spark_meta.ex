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
    state_machine: %{present: false, states: [], transitions: [], state_attribute: nil},
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
    last_modified: nil
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

defmodule Foundry.SparkMeta.Action do
  @moduledoc "Structured representation of an Ash resource action."
  defstruct [:name, :type, :description]
end

defmodule Foundry.SparkMeta.StepEntry do
  @moduledoc "Structured representation of a Reactor step."
  defstruct [:name, :type, :description, :target_module]
end

defmodule Foundry.SparkMeta.MoneyAttr do
  @moduledoc "Structured representation of a monetary attribute."
  defstruct [:name, :type, :cldr_backend]
end

defmodule Foundry.SparkMeta do
  @moduledoc """
  Generic Spark DSL walker for introspecting compiled modules.

  Produces SparkMeta.ModuleInfo structs without Foundry-specific assumptions.
  This module will become the `spark_meta` Hex package (ADR-019).

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
    # paper_trail, archival, auth_subject
    |> put_extension_fields()
    # AshStateMachine entities
    |> put_state_machine()
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
      case module.__info__(:attributes)[:moduledoc] do
        [{_line, doc}] when is_binary(doc) ->
          doc
          |> String.split("\n\n")
          |> Enum.reject(&(String.trim(&1) == ""))
          |> List.first()
          |> then(&if &1, do: String.trim(&1), else: nil)

        _ ->
          nil
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
          Spark.Dsl.Extension.get_entities(module, [:state_machine, :states])
          |> Enum.map(&to_string(&1.name))
        rescue
          _ -> []
        end

      transitions =
        try do
          Spark.Dsl.Extension.get_entities(module, [:state_machine, :transitions])
          |> Enum.map(fn t ->
            %{from: to_string(t.from), to: to_string(t.to), action: to_string(t.action)}
          end)
        rescue
          _ -> []
        end

      state_attr =
        try do
          Spark.Dsl.Extension.get_opt(module, [:state_machine], :state_attribute, nil)
          |> then(&if &1, do: to_string(&1), else: nil)
        rescue
          _ -> nil
        end

      %{
        info
        | state_machine: %{
            present: true,
            states: states,
            transitions: transitions,
            state_attribute: state_attr
          }
      }
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
          |> Enum.filter(&match?(%{__struct__: Reactor.Dsl.Step}, &1))
          |> Enum.map(fn step ->
            %{
              name: to_string(step.name),
              type:
                step.__struct__
                |> Module.split()
                |> List.last()
                |> String.downcase(),
              description: Map.get(step, :description),
              target_module: Map.get(step, :impl) || Map.get(step, :resource)
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

  defp put_oban_fields(%ModuleInfo{module: module} = info) do
    behaviours =
      try do
        module.__info__(:attributes) |> Keyword.get(:behaviour, [])
      rescue
        _ -> []
      end

    if Oban.Worker in behaviours do
      # Extract queue names from Oban DSL
      queues =
        try do
          Spark.Dsl.Extension.get_entities(module, [:oban])
          |> Enum.map(&to_string(&1.queue))
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
          foundry_config = get_attr_single(module.__info__(:attributes), :foundry)

          if is_map(foundry_config) do
            case Map.get(foundry_config, :performs) do
              atom when is_atom(atom) -> Atom.to_string(atom)
              string when is_binary(string) -> string
              _ -> nil
            end
          else
            nil
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
    function_exported?(module, :__ash_resource__, 0)
  rescue
    _ -> false
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

      Enum.any?(behaviours, &(&1 in [Ash.Policy.Check, Ash.Policy.SimpleCheck]))
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
    if function_exported?(module, :__spark_dsl_config__, 0) do
      Spark.extensions(module)
    else
      []
    end
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
    parts = String.split(module_str, ".")
    filename_lower =
      (parts
       |> Enum.drop(1)
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

defmodule Foundry.SparkMeta.Extension do
  @moduledoc """
  Opt-in hook for Spark extension authors to provide richer walker output.

  Implement this behaviour in your extension module to supply structured data
  that SparkMeta cannot derive from the generic Spark DSL introspection API.

  Unknown extensions (those not implementing this behaviour) receive a raw
  key-value fallback via Spark.Dsl.Extension.get_entities/3 — they do not
  cause crashes or produce missing data.
  """

  @callback enrich(module :: module(), info :: Foundry.SparkMeta.ModuleInfo.t()) ::
              Foundry.SparkMeta.ModuleInfo.t()
end
