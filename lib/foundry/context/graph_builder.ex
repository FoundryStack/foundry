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
  alias Foundry.SparkMeta, as: FoundrySparkMeta

  @spec build(String.t(), list()) :: {list(NodeEntry.t()), list(EdgeEntry.t())}
  def build(project_root, manifest) do
    root_name = Keyword.get(manifest, :project_name, "")
    {:ok, pending_set} = PendingMigrations.check(project_root)

    nodes =
      ModuleDiscovery.all_project_modules(project_root, root_name)
      |> Task.async_stream(
        fn mod ->
          info = FoundrySparkMeta.walk(mod)
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

        step_name = Map.get(step, :name) || Map.get(step, "name")
        step_index = Map.get(step, :step_index) || Map.get(step, "step_index")
        target_action = infer_step_action_name(step)

        Enum.map(
          read_targets,
          &new_step_edge(reactor.module, &1, :reads, step_name, step_index, target_action)
        ) ++
          Enum.map(
            write_targets,
            &new_step_edge(reactor.module, &1, :writes, step_name, step_index, target_action)
          )
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

  # Resource relationships: derived directly from live resource structure.
  defp derive_resource_edges(nodes, node_map) do
    known_modules = Map.keys(node_map) |> MapSet.new()

    nodes
    |> Enum.filter(&(&1.type == "resource"))
    |> Enum.flat_map(fn resource ->
      resource.module
      |> to_existing_module()
      |> relationship_edges_for(known_modules)
      |> Enum.map(&EdgeEntry.new(resource.module, &1.to, &1.relation))
    end)
  end

  # Authentication edges: authentication subjects connect to token resources.
  defp derive_auth_edges(nodes, node_map) do
    known_modules = Map.keys(node_map) |> MapSet.new()

    nodes
    |> Enum.filter(&(&1.authentication_subject == true))
    |> Enum.flat_map(fn user_node ->
      explicit_tokens =
        user_node.module
        |> to_existing_module()
        |> auth_token_resources()

      (explicit_tokens ++ implicit_auth_targets(user_node, explicit_tokens))
      |> Enum.uniq()
      |> Enum.filter(&MapSet.member?(known_modules, &1))
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

  # Rule usage edges are derived from normalized step.rules_applied facts.
  # This keeps graph links source-truthful (rule evaluate/check calls), not prose-driven.
  defp derive_rule_edges(nodes, node_map) do
    nodes
    |> Enum.filter(&(&1.type in ["reactor", "transfer"]))
    |> Enum.flat_map(fn reactor ->
      reactor.steps
      |> Enum.flat_map(fn step ->
        rule_refs = Map.get(step, :rules_applied) || Map.get(step, "rules_applied") || []
        step_name = Map.get(step, :name) || Map.get(step, "name")
        step_index = Map.get(step, :step_index) || Map.get(step, "step_index")

        rule_refs
        |> Enum.filter(&(Map.has_key?(node_map, &1) and node_map[&1].type == "rule"))
        |> Enum.map(fn rule_module ->
          %EdgeEntry{
            from: rule_module,
            to: reactor.module,
            relation: :guards,
            step_name: step_name && to_string(step_name),
            step_index: step_index
          }
        end)
      end)
    end)
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
              check_modules = policy_check_modules(policy, node_map)
              scoped_actions = policy_action_names(policy, resource.actions)

              case scoped_actions do
                [] ->
                  Enum.map(check_modules, &EdgeEntry.new(&1, resource.module, :guards))

                action_names ->
                  for check_module <- check_modules,
                      action_name <- action_names do
                    %EdgeEntry{
                      from: check_module,
                      to: resource.module,
                      relation: :guards,
                      action_name: action_name
                    }
                  end
              end
            end)
          else
            []
          end
      end
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

  defp format_module(nil), do: nil

  defp format_module(module) when is_atom(module) do
    module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp format_module(module) when is_binary(module), do: module
  defp format_module(_), do: nil

  defp relationship_edges_for(nil, _known_modules), do: []

  defp relationship_edges_for(module, known_modules) do
    module
    |> Ash.Resource.Info.relationships()
    |> Enum.filter(fn relationship ->
      Map.get(relationship, :public?, true) ||
        not String.starts_with?(to_string(Map.get(relationship, :name, "")), "paper_trail")
    end)
    |> Enum.flat_map(fn relationship ->
      related = format_module(Map.get(relationship, :destination))

      if is_binary(related) and MapSet.member?(known_modules, related) do
        case relationship_type(relationship) do
          :belongs_to ->
            [%{to: related, relation: :references}]

          :has_many ->
            [%{to: related, relation: :referenced_by}]

          :has_one ->
            [%{to: related, relation: :referenced_by}]

          :many_to_many ->
            [%{to: related, relation: :references}, %{to: related, relation: :referenced_by}]

          _ ->
            []
        end
      else
        []
      end
    end)
  rescue
    _ -> []
  end

  defp relationship_type(%{__struct__: struct_module}) do
    case struct_module do
      Ash.Resource.Relationships.BelongsTo -> :belongs_to
      Ash.Resource.Relationships.HasMany -> :has_many
      Ash.Resource.Relationships.HasOne -> :has_one
      Ash.Resource.Relationships.ManyToMany -> :many_to_many
      _ -> :unknown
    end
  end

  defp relationship_type(_relationship), do: :unknown

  defp auth_token_resources(nil), do: []

  defp auth_token_resources(module) do
    if SparkMeta.spark_module?(module) do
      global_token_resource =
        module
        |> SparkMeta.get_opt([:authentication, :tokens], :token_resource, nil)
        |> format_module()

      module
      |> SparkMeta.entities([:authentication, :strategies])
      |> Enum.map(fn strategy ->
        token_resource =
          strategy
          |> Map.get(:token_resource)
          |> format_module()

        token_resource || global_token_resource
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  rescue
    _ -> []
  end

  defp implicit_auth_targets(user_node, []),
    do: ["#{user_app_prefix(user_node)}.#{user_node.domain}.Token"]

  defp implicit_auth_targets(_user_node, _explicit_tokens), do: []

  defp user_app_prefix(user_node) do
    user_node.module
    |> String.split(".")
    |> List.first()
  end

  defp normalize_emitted_target(target) when is_binary(target) do
    case String.starts_with?(target, "Elixir.") do
      true -> String.replace_prefix(target, "Elixir.", "")
      false -> target
    end
  end

  defp new_step_edge(from, to, relation, step_name, step_index, action_name) do
    %EdgeEntry{
      from: from,
      to: to,
      relation: relation,
      step_name: step_name && to_string(step_name),
      step_index: step_index,
      action_name: action_name
    }
  end

  defp infer_step_action_name(step) do
    explicit_action =
      step
      |> Map.get(:target_action)
      |> Kernel.||(Map.get(step, "target_action"))
      |> normalize_action_name()

    explicit_action ||
      step
      |> Map.get(:source_snippet)
      |> Kernel.||(Map.get(step, "source_snippet"))
      |> infer_action_name_from_source()
  end

  defp infer_action_name_from_source(nil), do: nil

  defp infer_action_name_from_source(source_snippet) when is_binary(source_snippet) do
    with [_, action_name] <-
           Regex.run(
             ~r/Ash\.(?:create|update|destroy|get|read|read_one)\(\s*[^,\n]+,\s*:(\w+)/m,
             source_snippet
           ) do
      action_name
    else
      _ ->
        with [_, action_name] <-
               Regex.run(
                 ~r/Ash\.(?:create|update|destroy|get|read|read_one)\([^)]*action:\s*:(\w+)/m,
                 source_snippet
               ) do
          action_name
        else
          _ -> nil
        end
    end
  end

  defp infer_action_name_from_source(_source_snippet), do: nil

  defp policy_check_modules(policy, node_map) do
    policy
    |> Map.get(:policies, [])
    |> Enum.map(&Map.get(&1, :check_module))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&format_module/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&Map.has_key?(node_map, &1))
    |> Enum.uniq()
  end

  defp policy_action_names(policy, resource_actions) do
    policy
    |> Map.get(:condition, [])
    |> Enum.flat_map(&policy_condition_action_names(&1, resource_actions))
    |> Enum.uniq()
  end

  defp policy_condition_action_names({Ash.Policy.Check.Action, opts}, _resource_actions) do
    opts
    |> Keyword.get(:action, [])
    |> List.wrap()
    |> Enum.map(&normalize_action_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp policy_condition_action_names({Ash.Policy.Check.ActionType, opts}, resource_actions) do
    action_types =
      opts
      |> Keyword.get(:type, [])
      |> List.wrap()
      |> Enum.map(&normalize_action_type/1)
      |> Enum.reject(&is_nil/1)

    resource_actions
    |> List.wrap()
    |> Enum.filter(fn action ->
      action_type =
        action
        |> Map.get(:type)
        |> normalize_action_type()

      action_type in action_types
    end)
    |> Enum.map(fn action ->
      action
      |> Map.get(:name)
      |> normalize_action_name()
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp policy_condition_action_names(_condition, _resource_actions), do: []

  defp normalize_action_name(nil), do: nil

  defp normalize_action_name(action_name) when is_atom(action_name),
    do: Atom.to_string(action_name)

  defp normalize_action_name(action_name) when is_binary(action_name), do: action_name
  defp normalize_action_name(_action_name), do: nil

  defp normalize_action_type(nil), do: nil

  defp normalize_action_type(action_type) when is_atom(action_type),
    do: Atom.to_string(action_type)

  defp normalize_action_type(action_type) when is_binary(action_type), do: action_type
  defp normalize_action_type(_action_type), do: nil

  defp ash_resource_module?(module) do
    Ash.Resource.Info.resource?(module)
  rescue
    _ -> false
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
        [
          %NodeEntry{
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
          }
        ]
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
      [_, name] ->
        String.downcase(name)

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
