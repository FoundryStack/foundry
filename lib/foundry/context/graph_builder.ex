defmodule Foundry.Context.GraphBuilder do
  @moduledoc """
  Assembles the complete project graph by collecting all nodes and deriving edges
  between them based on structural and behavioral relationships.

  Edge derivation rules:
  - Reactor `:create`/`:update` steps → resource: `writes` edge
  - Reactor `:read`/`:read_one` steps → resource: `reads` edge
  - Oban worker with `@performs` → Reactor: `async` edge
  - Resource `belongs_to` relationship: `references` edge
  - Resource `has_many`/`has_one` relationship: `referenced_by` edge
  """

  alias Foundry.Context.{ModuleDiscovery, NodeBuilder, PendingMigrations, EdgeEntry, NodeEntry}
  alias Foundry.SparkMeta

  @spec build(String.t(), list()) :: {list(NodeEntry.t()), list(EdgeEntry.t())}
  def build(project_root, manifest) do
    root_name = Keyword.get(manifest, :project_name, "")
    {:ok, pending_set} = PendingMigrations.check(project_root)

    nodes =
      ModuleDiscovery.all_project_modules(project_root, root_name)
      |> Task.async_stream(
        fn mod ->
          info = SparkMeta.walk(mod)
          pending = PendingMigrations.pending?(mod, pending_set)
          NodeBuilder.build(info, manifest, pending)
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, node} -> node end)
      |> Enum.sort_by(& &1.id)

    edges =
      nodes
      |> derive_edges()
      |> Enum.sort_by(&{&1.from, &1.to})

    # Add external infrastructure nodes and their edges (Phase C)
    {external_nodes, external_edges} = derive_external_nodes_and_edges(nodes)
    all_nodes = Enum.sort_by(nodes ++ external_nodes, & &1.id)
    all_edges = Enum.sort_by(edges ++ external_edges, &{&1.from, &1.to})

    {all_nodes, all_edges}
  end

  # ---------------------------------------------------------------------------
  # Edge derivation
  # ---------------------------------------------------------------------------

  defp derive_edges(nodes) do
    edge_list = []

    # Build a map for quick lookup: module_fqn -> node
    node_map = Map.new(nodes, fn node -> {node.module, node} end)

    # Derive edges from all sources
    edge_list = edge_list ++ derive_reactor_edges(nodes, node_map)
    edge_list = edge_list ++ derive_job_edges(nodes, node_map)
    edge_list = edge_list ++ derive_resource_edges(nodes, node_map)
    edge_list = edge_list ++ derive_auth_edges(nodes, node_map)
    edge_list = edge_list ++ derive_rule_edges(nodes, node_map)
    edge_list = edge_list ++ derive_policy_edges(nodes, node_map)
    edge_list = edge_list ++ derive_provider_edges(nodes, node_map)
    edge_list = edge_list ++ derive_blueprint_edges(nodes, node_map)
    edge_list = edge_list ++ derive_trigger_edges(nodes, node_map)

    Enum.uniq(edge_list)
  end

  # Reactor steps: data-driven derivation from normalized read_targets/write_targets.
  defp derive_reactor_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.type in ["reactor", "transfer"]))
    |> Enum.flat_map(fn reactor ->
      reactor.steps
      |> Enum.flat_map(fn step ->
        read_targets =
          Map.get(step, :read_targets) || Map.get(step, "read_targets") ||
            fallback_targets(step, :read)

        write_targets =
          Map.get(step, :write_targets) || Map.get(step, "write_targets") ||
            fallback_targets(step, :write)

        Enum.map(read_targets, &EdgeEntry.new(reactor.module, &1, :reads)) ++
          Enum.map(write_targets, &EdgeEntry.new(reactor.module, &1, :writes))
      end)
    end)
  end

  # Oban jobs: linking to Reactor via @performs attribute or domain heuristic
  defp derive_job_edges(nodes, node_map) do
    nodes
    |> Enum.filter(&(&1.type == "job"))
    |> Enum.flat_map(fn job ->
      cond do
        job.performs ->
          [EdgeEntry.new(job.module, job.performs, :async)]
        true ->
          reactor = find_reactor_in_domain(node_map, job.domain)
          if reactor, do: [EdgeEntry.new(job.module, reactor.module, :async)], else: []
      end
    end)
  end

  # Helper: find a reactor in the same domain as the job
  defp find_reactor_in_domain(node_map, domain) do
    node_map
    |> Enum.find(fn {_module, node} ->
      node.type == "reactor" and node.domain == domain
    end)
    |> then(&if &1, do: elem(&1, 1), else: nil)
  end

  # Resource relationships: driven by relationship data from SparkMeta
  defp derive_resource_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.type == "resource"))
    |> Enum.flat_map(fn resource ->
      resource.relationships
      |> Enum.flat_map(fn rel ->
        rel_type = Map.get(rel, :type) || Map.get(rel, "type")
        related = Map.get(rel, :related_resource) || Map.get(rel, "related_resource")

        if related do
          case rel_type do
            :belongs_to ->
              [EdgeEntry.new(resource.module, related, :references)]
            "belongs_to" ->
              [EdgeEntry.new(resource.module, related, :references)]
            :has_many ->
              [EdgeEntry.new(resource.module, related, :referenced_by)]
            "has_many" ->
              [EdgeEntry.new(resource.module, related, :referenced_by)]
            :has_one ->
              [EdgeEntry.new(resource.module, related, :referenced_by)]
            "has_one" ->
              [EdgeEntry.new(resource.module, related, :referenced_by)]
            :many_to_many ->
              [
                EdgeEntry.new(resource.module, related, :references),
                EdgeEntry.new(resource.module, related, :referenced_by)
              ]
            "many_to_many" ->
              [
                EdgeEntry.new(resource.module, related, :references),
                EdgeEntry.new(resource.module, related, :referenced_by)
              ]
            _ ->
              []
          end
        else
          []
        end
      end)
    end)
  end

  # Authentication edges: User resource with auth_strategies → token resources
  defp derive_auth_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.authentication_subject == true))
    |> Enum.flat_map(fn user_node ->
      # Try to find token resource from auth_strategies or use heuristic
      explicit_tokens =
        user_node.auth_strategies
        |> Enum.filter(&(&1.token_resource != nil))
        |> Enum.map(& &1.token_resource)

      implicit_tokens =
        if Enum.empty?(explicit_tokens) do
          # Fallback heuristic: token resource is usually {AppPrefix}.{Domain}.Token
          app_prefix =
            user_node.module
            |> String.split(".")
            |> List.first()

          ["#{app_prefix}.#{user_node.domain}.Token"]
        else
          []
        end

      (explicit_tokens ++ implicit_tokens)
      |> Enum.uniq()
      |> Enum.map(&EdgeEntry.new(user_node.module, &1, :authenticates))
    end)
  end

  # Provider edges: connect provider adapter modules to external provider systems
  defp derive_provider_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.type == "provider"))
    |> Enum.flat_map(fn provider ->
      provider_name = extract_provider_name(provider)
      [EdgeEntry.new(provider.module, "external:#{provider_name}", :calls_provider)]
    end)
  end

  # Rule edges: derive guarded consumers from Reactor/Transfer step usage first, then
  # fall back to the legacy "Applied by:" prose parsing for standalone rules.
  defp derive_rule_edges(nodes, node_map) do
    consumer_edges =
      nodes
      |> Enum.filter(&(&1.type in ["reactor", "transfer"]))
      |> Enum.flat_map(fn consumer ->
        consumer.steps
        |> Enum.flat_map(fn step ->
          (Map.get(step, :rules_applied) || Map.get(step, "rules_applied") || [])
          |> Enum.filter(&Map.has_key?(node_map, &1))
          |> Enum.map(&EdgeEntry.new(&1, consumer.module, :guards))
        end)
      end)

    fallback_edges =
      nodes
      |> Enum.filter(&(&1.type == "rule"))
      |> Enum.flat_map(fn rule ->
        parse_applied_by_from_source(rule.module)
        |> Enum.filter(&Map.has_key?(node_map, &1))
        |> Enum.map(&EdgeEntry.new(rule.module, &1, :guards))
      end)

    consumer_edges ++ fallback_edges
  end

  defp derive_policy_edges(nodes, node_map) do
    nodes
    |> Enum.filter(&(&1.type == "resource"))
    |> Enum.flat_map(fn resource ->
      resource.module
      |> to_existing_module()
      |> case do
        nil ->
          []

        module ->
          if ash_resource_module?(module) do
            module
            |> Ash.Policy.Info.policies()
            |> Enum.flat_map(fn policy ->
              policy.policies
              |> Enum.map(&Map.get(&1, :check_module))
              |> Enum.reject(&is_nil/1)
            end)
            |> Enum.map(&format_module/1)
            |> Enum.filter(&Map.has_key?(node_map, &1))
            |> Enum.uniq()
            |> Enum.map(&EdgeEntry.new(&1, resource.module, :guards))
          else
            []
          end
      end
    end)
  end

  # Blueprint edges: detect which reactors/transfers a blueprint configures
  # Parse "Used by:" entries from blueprint description
  defp derive_blueprint_edges(nodes, node_map) do
    nodes
    |> Enum.filter(&(&1.type == "blueprint"))
    |> Enum.flat_map(fn blueprint ->
      used_by_targets = parse_used_by_from_description(blueprint.description)

      used_by_targets
      |> Enum.filter(&Map.has_key?(node_map, &1))
      |> Enum.map(&EdgeEntry.new(blueprint.module, &1, :configures))
    end)
  end

  defp derive_trigger_edges(nodes, node_map) do
    nodes
    |> Enum.filter(&(&1.type == "trigger"))
    |> Enum.flat_map(fn trigger ->
      trigger.side_effects
      |> Enum.flat_map(fn side_effect ->
        case side_effect.type do
          :oban_emit ->
            target = normalize_emitted_target(side_effect.name)

            if Map.has_key?(node_map, target) do
              [EdgeEntry.new(trigger.module, target, :enqueues)]
            else
              []
            end

          _ ->
            []
        end
      end)
    end)
  end

  # Parse "Used by: Module.A, Module.B" from blueprint description
  # Matches pattern: "Used by: " followed by comma/newline-separated modules
  defp parse_used_by_from_description(text) when is_nil(text), do: []
  defp parse_used_by_from_description(text) do
    case Regex.run(~r/Used by:\s*(.*?)(?:\n\n|\z)/s, text) do
      [_, list] ->
        list
        |> String.split(~r/[,\n]/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      _ ->
        []
    end
  end

  # Parse "Applied by: Module.A, Module.B" from rule description
  # Matches pattern: "Applied by: " followed by comma/newline-separated modules
  defp parse_applied_by_from_description(text) do
    case Regex.run(~r/Applied by:\s*(.*?)(?:\n\n|\z)/s, text) do
      [_, list] ->
        list
        |> String.split(~r/[,\n]/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      _ ->
        []
    end
  end

  # Fallback: try to find "Applied by:" in the source file
  defp parse_applied_by_from_source(module_name) do
    # Convert module name to file path and try to read source
    # Module paths like "IgamingRef.Finance.Rules.SufficientBalance" -> search in rules.ex
    case find_module_source_section(module_name) do
      {:ok, section} ->
        parse_applied_by_from_description(section)
      :error ->
        []
    end
  rescue
    _ -> []
  end

  defp fallback_targets(step, expected_kind) do
    target_resource = Map.get(step, :target_resource) || Map.get(step, "target_resource")
    step_kind = Map.get(step, :step_kind) || Map.get(step, "step_kind")

    cond do
      expected_kind == :read and step_kind in [:read, "read"] and is_binary(target_resource) ->
        [target_resource]

      expected_kind == :write and step_kind in [:write, "write"] and is_binary(target_resource) ->
        [target_resource]

      true ->
        []
    end
  end

  defp to_existing_module(module_name) when is_binary(module_name) do
    String.to_existing_atom("Elixir." <> module_name)
  rescue
    _ -> nil
  end

  defp format_module(module) when is_atom(module) do
    module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp format_module(module) when is_binary(module), do: module
  defp format_module(_), do: nil

  defp normalize_emitted_target(target) when is_binary(target) do
    case String.starts_with?(target, "Elixir.") do
      true -> String.replace_prefix(target, "Elixir.", "")
      false -> target
    end
  end

  defp ash_resource_module?(module) do
    function_exported?(module, :__ash_resource__, 0)
  rescue
    _ -> false
  end

  # Helper: find module source section (the moduledoc for this specific rule)
  defp find_module_source_section(module_name) do
    try do
      module_atom = String.to_existing_atom("Elixir." <> module_name)
      case module_atom.__info__(:compile) do
        compile_info when is_list(compile_info) ->
          source = Keyword.get(compile_info, :source)
          # Source may be a charlist or string
          source_path =
            if is_list(source) do
              source |> to_string()
            else
              source
            end

          if source_path && File.exists?(source_path) do
            content = File.read!(source_path)
            # Extract just the module's section
            # Find "defmodule <ModuleName>" and get the next ~25 lines
            # (this covers the @moduledoc, @compliance, @spec_invariants comments)
            module_short_name = module_name |> String.split(".") |> List.last()
            pattern = "defmodule.*#{Regex.escape(module_short_name)} do"

            case Regex.run(~r/#{pattern}/m, content, return: :index) do
              [{start_pos, _length}] ->
                # Extract ~30 lines starting from this position
                rest = String.slice(content, start_pos..-1//1)
                lines = String.split(rest, "\n") |> Enum.take(30) |> Enum.join("\n")
                {:ok, lines}
              _ ->
                :error
            end
          else
            :error
          end
        _ -> :error
      end
    rescue
      _ -> :error
    end
  end

  # ---------------------------------------------------------------------------
  # External node synthesis (Phase C)
  # ---------------------------------------------------------------------------

  defp derive_external_nodes_and_edges(nodes) do
    # Collect edges to external systems, grouped by domain for postgres
    postgres_by_domain =
      for n <- nodes,
          n.type == "resource",
          n.data_layer && String.contains?(to_string(n.data_layer), "AshPostgres"),
          reduce: %{} do
        acc ->
          domain = n.domain
          edge = EdgeEntry.new(n.module, "external:postgres:#{domain}", :persists_to)
          Map.update(acc, domain, [edge], fn edges -> edges ++ [edge] end)
      end

    postgres_edges = postgres_by_domain |> Map.values() |> Enum.concat()

    oban_edges =
      for n <- nodes,
          n.type == "job",
          n.oban_queues && length(n.oban_queues) > 0,
          do: EdgeEntry.new(n.module, "external:oban_queue", :queues_via)

    # Collect provider edges and extract unique provider names
    provider_edges =
      for n <- nodes,
          n.type == "provider",
          do: EdgeEntry.new(n.module, "external:#{extract_provider_name(n)}", :calls_provider)

    provider_names =
      provider_edges
      |> Enum.map(& &1.to)
      |> Enum.uniq()

    external_edges = postgres_edges ++ oban_edges ++ provider_edges

    # Create external postgres nodes for each domain that has AshPostgres resources
    postgres_nodes =
      postgres_by_domain
      |> Enum.map(fn {domain, _edges} ->
        %NodeEntry{
          module: "external:postgres:#{domain}",
          id: "external:postgres:#{domain}",
          type: "external",
          domain: "Infrastructure",
          description: "PostgreSQL - #{domain} domain tables (AshPostgres)",
          app: nil,
          sensitive: false,
          attributes: [],
          actions: [],
          rules: [],
          compliance: [],
          adrs: [],
          runbook: nil,
          test_coverage: %{property_tests: false, scenario_tests: false, e2e_tests: false},
          data_layer: nil,
          pending_migrations: false,
          paper_trail: false,
          archival: false,
          state_machine: nil,
          api_routes: [],
          telemetry_prefix: nil,
          money_attributes: [],
          authentication_subject: false,
          oban_queues: [],
          rate_limited: false,
          feature_flags: [],
          steps: [],
          performs: nil,
          outputs: [],
          agent_steps: [],
          relationships: [],
          auth_strategies: [],
          last_modified: nil
        }
      end)

    # Oban external node (singleton)
    oban_node =
      if length(oban_edges) > 0 do
        [%NodeEntry{
          module: "external:oban_queue",
          id: "external:oban_queue",
          type: "external",
          domain: "Infrastructure",
          description: "Oban background job queue",
          app: nil,
          sensitive: false,
          attributes: [],
          actions: [],
          rules: [],
          compliance: [],
          adrs: [],
          runbook: nil,
          test_coverage: %{property_tests: false, scenario_tests: false, e2e_tests: false},
          data_layer: nil,
          pending_migrations: false,
          paper_trail: false,
          archival: false,
          state_machine: nil,
          api_routes: [],
          telemetry_prefix: nil,
          money_attributes: [],
          authentication_subject: false,
          oban_queues: [],
          rate_limited: false,
          feature_flags: [],
          steps: [],
          performs: nil,
          outputs: [],
          agent_steps: [],
          relationships: [],
          auth_strategies: [],
          last_modified: nil
        }]
      else
        []
      end

    # Provider external nodes
    provider_nodes =
      provider_names
      |> Enum.map(fn provider_id ->
        # Extract provider name from "external:provider_name"
        provider_name = String.replace(provider_id, "external:", "")
        human_name = humanize_provider_name(provider_name)
        %NodeEntry{
          module: provider_id,
          id: provider_id,
          type: "external",
          domain: "Infrastructure",
          description: "External API: #{human_name}",
          app: nil,
          sensitive: false,
          attributes: [],
          actions: [],
          rules: [],
          compliance: [],
          adrs: [],
          runbook: nil,
          test_coverage: %{property_tests: false, scenario_tests: false, e2e_tests: false},
          data_layer: nil,
          pending_migrations: false,
          paper_trail: false,
          archival: false,
          state_machine: nil,
          api_routes: [],
          telemetry_prefix: nil,
          money_attributes: [],
          authentication_subject: false,
          oban_queues: [],
          rate_limited: false,
          feature_flags: [],
          steps: [],
          performs: nil,
          outputs: [],
          agent_steps: [],
          relationships: [],
          auth_strategies: [],
          last_modified: nil
        }
      end)

    external_nodes = postgres_nodes ++ oban_node ++ provider_nodes

    {external_nodes, external_edges}
  end

  # Extract provider name from a provider node
  defp extract_provider_name(provider) do
    case Regex.run(~r/@provider_name\s+"([^"]+)"/, provider.description || "") do
      [_, name] -> String.downcase(name)
      _ ->
        # Fallback: use last segment of module name in snake_case
        provider.module
        |> String.split(".")
        |> List.last()
        |> String.downcase()
    end
  end

  # Humanize provider name for display in external node descriptions
  # e.g. "pragmaticplayv1" -> "Pragmatic Play V1"
  defp humanize_provider_name(provider_name) do
    provider_name
    |> String.split(~r/(?=[A-Z])|_/)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
