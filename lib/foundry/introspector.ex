defmodule Foundry.Context.Introspector do
  @moduledoc """
  Core Spark DSL introspection logic for `mix foundry.context` and
  `mix foundry.context.all`.

  Reads compiled modules via `Spark.Dsl.Extension` introspection and maps
  them to `Foundry.Context.ModuleContext` structs. All reads are against
  the live compiled beam — never against source text.

  ## Module type detection

  Detection order (first match wins):
  1. Implements `AshAuthentication` subject → `:resource` (auth)
  2. Uses `Ash.Resource` → `:resource`
  3. Uses `Reactor` with Transfer DSL → `:transfer`
  4. Uses `Reactor` → checked for Oban worker pattern → `:oban_job`
  5. Uses Foundry `Rule` DSL → `:rule`
  6. Uses Foundry `Blueprint` DSL → `:blueprint`
  7. Uses `Phoenix.LiveView` + LiveResource → `:live_page`
  8. Implements provider adapter behaviour → `:adapter`

  ## Caller responsibility

  The caller (Mix task) is responsible for ensuring the target project is
  compiled and its modules are loaded before calling into this module.
  `Introspector` never calls `Mix.Task.run("compile")` itself.

  ## Sensitive detection

  A module is marked `sensitive: true` when its string name appears in
  `manifest.sensitive_resources`, or when it is an `ash_authentication`
  User/Token resource.
  """

  alias Foundry.Context.ModuleContext
  alias Foundry.PageMetadata

  @type opts :: [
          manifest_path: String.t(),
          project_root: String.t()
        ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Build a `ModuleContext` for a single module.

  Returns `{:ok, %ModuleContext{}}` or `{:error, reason}`.
  """
  @spec build(module(), opts()) :: {:ok, ModuleContext.t()} | {:error, term()}
  def build(mod, opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    manifest = load_manifest(project_root)
    sensitive_set = sensitive_set(manifest)

    {:ok, build_context(mod, sensitive_set, project_root, %{})}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Build `ModuleContext` structs for all Foundry-relevant modules in the
  compiled project, grouped by domain name string.

  Returns `%{domain_name => [ModuleContext.t()]}`.
  """
  @spec build_all(opts()) :: %{String.t() => [ModuleContext.t()]}
  def build_all(opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    manifest = load_manifest(project_root)
    sensitive_set = sensitive_set(manifest)
    excluded = excluded_set(manifest)
    app_name = Mix.Project.config()[:app]

    page_routes_map =
      case Foundry.Context.RouterIntrospector.find_router(app_name, project_root) do
        nil ->
          %{}

        router ->
          try do
            Foundry.Context.RouterIntrospector.liveview_routes(router)
            |> Map.new(fn route -> {route.module, route} end)
          rescue
            _ -> %{}
          end
      end

    # Discover page modules from router, or from module path pattern
    page_modules =
      case Map.keys(page_routes_map) do
        [] ->
          # Fallback: Find modules in Web.Live pattern
          all_modules()
          |> Enum.filter(fn mod ->
            mod_str = to_string(mod)

            (String.contains?(mod_str, ".Live.") or String.ends_with?(mod_str, "Live")) and
              page_module?(mod)
          end)

        routes ->
          routes
      end

    all_modules()
    |> Kernel.++(page_modules)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(excluded, to_string(&1)))
    |> Enum.filter(&foundry_relevant?/1)
    |> Enum.map(&build_context(&1, sensitive_set, project_root, page_routes_map))
    |> Enum.group_by(& &1.domain)
  end

  # ---------------------------------------------------------------------------
  # Module discovery
  # ---------------------------------------------------------------------------

  defp all_modules do
    # Load all beam modules from the project's _build directory.
    # We restrict to modules whose beam files live under _build/dev/lib/<app>/
    # to avoid introspecting dependencies.
    app_name = Mix.Project.config()[:app]
    beam_dir = Mix.Project.compile_path()

    beam_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".beam"))
    |> Enum.map(fn filename ->
      filename
      |> String.replace_suffix(".beam", "")
      |> String.to_atom()
    end)
    |> Enum.filter(fn mod ->
      # Ensure the module is loadable and belongs to this app
      case Code.ensure_loaded(mod) do
        {:module, ^mod} -> module_app(mod) == app_name
        _ -> false
      end
    end)
  end

  defp module_app(mod) do
    case :application.get_application(mod) do
      {:ok, app} -> app
      _ -> nil
    end
  end

  defp foundry_relevant?(mod) do
    ash_resource?(mod) or
      reactor_module?(mod) or
      rule_module?(mod) or
      blueprint_module?(mod) or
      live_page_module?(mod) or
      page_module?(mod) or
      adapter_module?(mod)
  end

  # ---------------------------------------------------------------------------
  # Type detection
  # ---------------------------------------------------------------------------

  defp ash_resource?(mod) do
    try do
      extensions = spark_extensions(mod)
      Ash.Resource in extensions
    rescue
      _ ->
        try do
          Spark.implements_behaviour?(mod, Ash.Resource.Behaviour)
        rescue
          _ -> false
        end
    end
  end

  defp reactor_module?(mod) do
    try do
      function_exported?(mod, :reactor, 0) or
        (function_exported?(mod, :spark_dsl_config, 0) and
           Reactor in spark_extensions(mod))
    rescue
      _ -> false
    end
  end

  defp rule_module?(mod) do
    # Rule modules use a @behaviour or a custom DSL macro.
    # Detection: module exports `evaluate/2` and has @rule_metadata attribute,
    # OR its name ends in .Rules.Something.
    function_exported?(mod, :evaluate, 2) and
      match?([_ | _], mod |> to_string() |> String.split(".") |> Enum.filter(&(&1 == "Rules")))
  end

  defp blueprint_module?(mod) do
    function_exported?(mod, :config_schema, 0) and
      function_exported?(mod, :eligibility_rules, 0)
  end

  defp live_page_module?(mod) do
    function_exported?(mod, :__live_resource__, 0)
  end

  defp page_module?(mod) do
    # A page module is a Phoenix LiveView discovered via router introspection
    # or explicitly declared with @page_group annotation.
    phoenix_live_view?(mod)
  end

  defp phoenix_live_view?(mod) do
    try do
      # Check if module has mount/3 function and is a Phoenix.LiveView
      has_mount =
        mod.__info__(:functions)
        |> Enum.any?(fn {name, arity} -> name == :mount and arity == 3 end)

      has_behaviour =
        Keyword.has_key?(mod.__info__(:attributes), :behaviour) and
          :phoenix_live_view in (mod.__info__(:attributes)[:behaviour] || [])

      has_mount and has_behaviour
    rescue
      _ -> false
    end
  end

  defp adapter_module?(mod) do
    function_exported?(mod, :verify_contract, 0) and
      function_exported?(mod, :adapter_name, 0)
  end

  defp spark_extensions(mod) do
    mod
    |> Spark.Dsl.Extension.get_persisted(:extensions)
    |> Kernel.||([])
  rescue
    _ -> []
  end

  # ---------------------------------------------------------------------------
  # Context building
  # ---------------------------------------------------------------------------

  defp build_context(mod, sensitive_set, project_root, page_routes_map) do
    mod_str = to_string(mod)
    type = detect_type(mod)
    domain = detect_domain(mod)

    # Extract page metadata if this is a page module
    {page_route, page_dynamic, page_group, page_subtype, calls_actions, page_feature_flags} =
      if type == :page do
        page_meta = PageMetadata.analyze(mod, Map.get(page_routes_map, mod))

        {
          page_meta[:page_route],
          page_meta[:page_dynamic] || false,
          page_meta[:page_group],
          page_meta[:page_subtype],
          page_meta[:calls_actions] || [],
          page_meta[:feature_flags] || []
        }
      else
        {nil, false, nil, nil, [], []}
      end

    %ModuleContext{
      module: mod_str,
      type: type,
      domain: domain,
      description: module_description(mod),
      steps: transfer_steps(mod, type),
      rules: applied_rules(mod, type),
      compliance: compliance_links(mod),
      runbook: runbook_path(mod),
      invariants: spec_invariants(mod),
      related_resources: related_resources(mod, type),
      adrs: adr_references(mod),
      last_modified: last_modified(mod, project_root),
      sensitive: MapSet.member?(sensitive_set, mod_str) or auth_resource?(mod),
      test_coverage: test_coverage(mod, project_root),
      data_layer: data_layer(mod, type),
      pending_migrations: pending_migrations?(mod, type),
      paper_trail: has_extension?(mod, AshPaperTrail.Resource),
      archival: has_extension?(mod, AshArchival.Resource),
      state_machine: state_machine_info(mod),
      api_routes: api_routes(mod),
      telemetry_prefix: telemetry_prefix(mod),
      money_attributes: money_attributes(mod, type),
      authentication_subject: auth_resource?(mod),
      oban_queues: oban_queues(mod, type),
      rate_limited: rate_limited?(mod),
      feature_flags: if(type == :page, do: page_feature_flags, else: feature_flags(mod)),
      page_route: page_route,
      page_group: page_group,
      page_dynamic: page_dynamic,
      page_subtype: page_subtype,
      calls_actions: calls_actions
    }
  end

  # ---------------------------------------------------------------------------
  # Field extractors
  # ---------------------------------------------------------------------------

  defp detect_type(mod) do
    cond do
      auth_resource?(mod) -> :resource
      ash_resource?(mod) -> :resource
      transfer_module?(mod) -> :transfer
      oban_worker?(mod) -> :oban_job
      rule_module?(mod) -> :rule
      blueprint_module?(mod) -> :blueprint
      page_module?(mod) -> :page
      live_page_module?(mod) -> :live_page
      adapter_module?(mod) -> :adapter
      true -> :resource
    end
  end

  defp transfer_module?(mod) do
    reactor_module?(mod) and function_exported?(mod, :__transfer_dsl__, 0)
  end

  defp oban_worker?(mod) do
    function_exported?(mod, :perform, 1) and
      Code.ensure_loaded?(Oban.Worker) and
      Oban.Worker in (mod.__info__(:attributes)[:behaviour] || [])
  rescue
    _ -> false
  end

  defp auth_resource?(mod) do
    try do
      extensions = spark_extensions(mod)

      AshAuthentication in extensions or
        AshAuthentication.TokenResource in extensions
    rescue
      _ -> false
    end
  end

  defp detect_domain(mod) do
    # Domain = Ash domain name (second segment after app root).
    # Elixir.IgamingRef.Finance.Wallet → "Finance"
    # Elixir.IgamingRef.Promotions.Rules.PlayerEligibleForCampaign → "Promotions"
    parts = mod |> to_string() |> String.split(".")

    case parts do
      ["Elixir", _app, domain | _rest] -> domain
      [_app, domain | _rest] -> domain
      [_app] -> "Root"
      _ -> "Unknown"
    end
  end

  defp module_description(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} ->
        doc
        |> String.split("\n\n")
        |> List.first()
        |> String.trim()

      _ ->
        mod |> to_string() |> String.split(".") |> List.last()
    end
  end

  defp transfer_steps(mod, :transfer) do
    try do
      mod.__transfer_dsl__()[:steps]
      |> Enum.map(&to_string/1)
    rescue
      _ ->
        # Fallback: read Reactor steps via Spark introspection
        Spark.Dsl.Extension.get_entities(mod, [:reactor, :steps])
        |> Enum.map(&(&1.name |> to_string()))
    end
  end

  defp transfer_steps(_, _), do: []

  defp applied_rules(mod, :transfer) do
    try do
      mod.__transfer_dsl__()[:rules] |> Enum.map(&to_string/1)
    rescue
      _ -> []
    end
  end

  defp applied_rules(_, _), do: []

  defp compliance_links(mod) do
    try do
      mod.__info__(:attributes)[:compliance] || []
    rescue
      _ -> []
    end
    |> Enum.map(&to_string/1)
  end

  defp runbook_path(mod) do
    try do
      mod.__info__(:attributes)[:runbook]
      |> List.wrap()
      |> List.first()
    rescue
      _ -> nil
    end
  end

  defp spec_invariants(mod) do
    try do
      (mod.__info__(:attributes)[:spec_invariants] || [])
      |> Enum.map(&to_string/1)
    rescue
      _ -> []
    end
  end

  defp related_resources(mod, type) when type in [:resource, :transfer] do
    try do
      case type do
        :resource ->
          Ash.Resource.Info.relationships(mod)
          |> Enum.map(&(&1.destination |> to_string()))

        :transfer ->
          # Extract from Reactor step inputs that reference Ash resources
          []
      end
    rescue
      _ -> []
    end
  end

  defp related_resources(_, _), do: []

  defp adr_references(mod) do
    # Parse @moduledoc for "ADR-NNN" references
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} ->
        Regex.scan(~r/ADR-\d{3}/, doc)
        |> List.flatten()
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp last_modified(mod, project_root) do
    # Find the source file via __info__ and read its mtime
    try do
      case mod.__info__(:compile)[:source] do
        nil ->
          nil

        source ->
          path = List.to_string(source)
          rel = Path.relative_to(path, project_root)

          case File.stat(Path.join(project_root, rel)) do
            {:ok, %{mtime: mtime}} ->
              mtime
              |> NaiveDateTime.from_erl!()
              |> NaiveDateTime.to_date()
              |> Date.to_iso8601()

            _ ->
              nil
          end
      end
    rescue
      _ -> nil
    end
  end

  defp test_coverage(mod, project_root) do
    mod_name = mod |> to_string() |> String.split(".") |> List.last()
    test_dir = Path.join(project_root, "test")

    property_tests =
      file_contains_pattern?(test_dir, "#{mod_name}Test", "stream_data") or
        file_contains_pattern?(test_dir, "#{mod_name}Test", "property test")

    scenario_tests =
      file_contains_pattern?(test_dir, "#{mod_name}", "scenario") or
        file_contains_pattern?(test_dir, "#{mod_name}", "@tag :scenario")

    e2e_tests =
      file_contains_pattern?(test_dir, "#{mod_name}", ":compliance") or
        file_contains_pattern?(test_dir, "#{mod_name}", ":e2e")

    %{
      property_tests: property_tests,
      scenario_tests: scenario_tests,
      e2e_tests: e2e_tests,
      scenario_count: 0
    }
  end

  defp file_contains_pattern?(test_dir, module_name, pattern) do
    case File.ls(test_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.contains?(&1, String.downcase(module_name)))
        |> Enum.any?(fn file ->
          path = Path.join(test_dir, file)

          case File.read(path) do
            {:ok, content} -> String.contains?(content, pattern)
            _ -> false
          end
        end)

      _ ->
        false
    end
  end

  defp data_layer(mod, type) when type == :resource do
    try do
      mod
      |> Spark.Dsl.Extension.get_persisted(:data_layer)
      |> case do
        Ash.DataLayer.Postgres -> "ash_postgres"
        AshPostgres.DataLayer -> "ash_postgres"
        Ash.DataLayer.Ets -> "ash_ets"
        Ash.DataLayer.Simple -> "simple"
        other when not is_nil(other) -> to_string(other)
        nil -> nil
      end
    rescue
      _ -> nil
    end
  end

  defp data_layer(_, _), do: nil

  defp pending_migrations?(_mod, :resource) do
    # Delegate to `mix ash.codegen --check` exit code via subprocess.
    # Returns false here — the Mix task itself performs the check at aggregate level.
    # Individual resource pending-migration status is too expensive to check per-module.
    false
  end

  defp pending_migrations?(_, _), do: false

  defp has_extension?(mod, extension) do
    extension in spark_extensions(mod)
  rescue
    _ -> false
  end

  defp state_machine_info(mod) do
    base = %{present: false, states: [], transitions: [], state_attribute: nil}

    try do
      unless has_extension?(mod, AshStateMachine), do: throw(:no_sm)

      states =
        Spark.Dsl.Extension.get_entities(mod, [:state_machine, :states])
        |> Enum.map(&(&1.name |> to_string()))

      transitions =
        Spark.Dsl.Extension.get_entities(mod, [:state_machine, :transitions])
        |> Enum.map(fn t ->
          %{
            from: t.from |> List.wrap() |> Enum.map(&to_string/1) |> Enum.join("|"),
            to: to_string(t.to),
            action: to_string(t.action)
          }
        end)

      state_attr =
        Spark.Dsl.Extension.get_opt(mod, [:state_machine], :state_attribute, :state)
        |> to_string()

      %{
        base
        | present: true,
          states: states,
          transitions: transitions,
          state_attribute: state_attr
      }
    rescue
      _ -> base
    catch
      _ -> base
    end
  end

  defp api_routes(mod) do
    try do
      Spark.Dsl.Extension.get_entities(mod, [:json_api, :routes])
      |> Enum.map(fn route ->
        %{
          path: route.route,
          method: route.method |> to_string() |> String.upcase(),
          auth_required: route.primary_key_source != nil
        }
      end)
    rescue
      _ -> []
    end
  end

  defp telemetry_prefix(mod) do
    try do
      (mod.__info__(:attributes)[:telemetry_prefix] || [])
      |> List.flatten()
      |> Enum.map(&to_string/1)
    rescue
      _ -> []
    end
  end

  defp money_attributes(mod, :resource) do
    try do
      Ash.Resource.Info.attributes(mod)
      |> Enum.filter(fn attr ->
        attr.type == Ash.Type.Money or
          (is_tuple(attr.type) and elem(attr.type, 0) == Ash.Type.Money)
      end)
      |> Enum.map(fn attr ->
        cldr_backend =
          attr.constraints[:storage_type]
          |> then(fn _ ->
            mod.__info__(:attributes)[:cldr_backend]
            |> List.wrap()
            |> List.first()
            |> to_string()
          end)

        %{name: to_string(attr.name), type: "Ash.Type.Money", cldr_backend: cldr_backend}
      end)
    rescue
      _ -> []
    end
  end

  defp money_attributes(_, _), do: []

  defp oban_queues(mod, :oban_job) do
    try do
      queue = mod.__info__(:attributes)[:queue] || []
      queue |> List.wrap() |> Enum.map(&to_string/1)
    rescue
      _ -> []
    end
  end

  defp oban_queues(_, _), do: []

  defp rate_limited?(mod) do
    try do
      plugs = mod.__info__(:attributes)[:plug] || []

      Enum.any?(plugs, fn
        {HammerPlug, _} -> true
        HammerPlug -> true
        _ -> false
      end)
    rescue
      _ -> false
    end
  end

  defp feature_flags(mod) do
    try do
      (mod.__info__(:attributes)[:feature_flags] || [])
      |> Enum.map(&to_string/1)
    rescue
      _ -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Manifest helpers
  # ---------------------------------------------------------------------------

  defp load_manifest(project_root) do
    path = Path.join([project_root, ".foundry", "manifest.exs"])

    case File.read(path) do
      {:ok, content} ->
        {kw, _} = Code.eval_string(content)
        kw

      _ ->
        []
    end
  end

  defp sensitive_set(manifest) do
    (manifest[:sensitive_resources] || [])
    |> Enum.map(&to_string/1)
    |> MapSet.new()
  end

  defp excluded_set(manifest) do
    (manifest[:context_exclusions] || [])
    |> Enum.map(&to_string/1)
    |> MapSet.new()
  end
end
