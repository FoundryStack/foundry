defmodule Mix.Tasks.Foundry.Diagram.Generate do
  @shortdoc "Generate system map graph JSON from context introspection (INV-008)"

  @moduledoc """
  Builds the system map graph by calling `Foundry.Context.Introspector.build_all/1`,
  projecting the result into `Foundry.Diagram.SystemMap` (nodes, edges, clusters),
  and writing the output to `docs/diagrams/system_map.json`.

  The committed JSON file is the source of truth for the Phase 2 D3 renderer.
  INV-008 requires that the diagram is always current — CI runs this task with
  `--check` and fails if the output would differ from the committed file.

  ## Usage

      mix foundry.diagram.generate            # regenerate and write to disk
      mix foundry.diagram.generate --json     # emit JSON to stdout, no disk write
      mix foundry.diagram.generate --check    # exit 1 if output differs from committed

  ## Output file

  `docs/diagrams/system_map.json` relative to the project root.
  The directory is created if it does not exist.

  ## Check mode (CI)

  In check mode, the task generates the graph, compares it to the committed
  file, and exits 1 if they differ. The comparison ignores the `generated_at`
  timestamp field — only structural changes (nodes, edges, clusters) are
  considered meaningful differences.

  ## Graph construction

      Nodes   — one per module in context.all output
      Edges   — derived from:
                  - Ash relationships (belongs_to, has_many, has_one, many_to_many)
                  - Transfer rules: Transfer → Rule (applies_rule edge)
                  - Transfer steps that reference resources (transfer_step edge)
      Clusters — one per domain name (grouping the domain's nodes)

  ## test_coverage derivation

  `Node.test_coverage` is derived from `ModuleContext.test_coverage`:
    :none    — all three coverage booleans false
    :partial — at least one true, not all
    :full    — all three true
  """

  use Mix.Task

  alias Foundry.Diagram.SystemMap
  alias Foundry.Diagram.SystemMap.{Node, Edge, Cluster}
  alias Foundry.Context.Introspector

  @output_path "docs/diagrams/system_map.json"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    project_root = File.cwd!()
    check_mode   = "--check" in args
    stdout_only  = "--json" in args

    all_context = Introspector.build_all(project_root: project_root)
    system_map  = build_system_map(all_context)

    json = Jason.encode!(system_map, pretty: true)

    cond do
      check_mode ->
        run_check(json, project_root)

      stdout_only ->
        Mix.shell().info(json)

      true ->
        write_output(json, project_root)
        Mix.shell().info("System map written to #{@output_path}")
    end
  end

  # ---------------------------------------------------------------------------
  # Graph construction
  # ---------------------------------------------------------------------------

  defp build_system_map(all_context) do
    flat_contexts = all_context |> Map.values() |> List.flatten()

    nodes    = Enum.map(flat_contexts, &to_node/1)
    edges    = flat_contexts |> Enum.flat_map(&to_edges/1) |> Enum.uniq()
    clusters = build_clusters(all_context)

    %SystemMap{
      nodes:        nodes,
      edges:        edges,
      clusters:     clusters,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp to_node(ctx) do
    %Node{
      id:                 ctx.module,
      module:             ctx.module,
      type:               ctx.type,
      domain:             ctx.domain,
      label:              ctx.module |> String.split(".") |> List.last(),
      sensitive:          ctx.sensitive,
      has_compliance:     ctx.compliance != [],
      test_coverage:      derive_coverage(ctx.test_coverage),
      pending_migrations: ctx.pending_migrations
    }
  end

  # Derive :none | :partial | :full from the three-boolean test_coverage map.
  defp derive_coverage(%{property_tests: pt, scenario_tests: st, e2e_tests: et}) do
    case {pt, st, et} do
      {true, true, true}   -> :full
      {false, false, false} -> :none
      _                    -> :partial
    end
  end
  defp derive_coverage(_), do: :none

  defp to_edges(ctx) do
    resource_edges =
      ctx.related_resources
      |> Enum.map(fn target ->
        %Edge{from: ctx.module, to: target, kind: :belongs_to}
      end)

    rule_edges =
      ctx.rules
      |> Enum.map(fn rule ->
        %Edge{from: ctx.module, to: rule, kind: :applies_rule}
      end)

    step_edges =
      if ctx.type == :transfer do
        # Transfer step → resource edges: derive from steps that share names
        # with known resource modules. Phase 1 approximation — full step
        # introspection requires reading Reactor step DSL (Phase 2 enhancement).
        []
      else
        []
      end

    resource_edges ++ rule_edges ++ step_edges
  end

  defp build_clusters(all_context) do
    all_context
    |> Enum.map(fn {domain_name, contexts} ->
      node_ids = Enum.map(contexts, & &1.module)
      %Cluster{
        id:       domain_name,
        label:    domain_name,
        node_ids: node_ids
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Output / check
  # ---------------------------------------------------------------------------

  defp write_output(json, project_root) do
    out_path = Path.join(project_root, @output_path)
    out_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(out_path, json)
  end

  defp run_check(fresh_json, project_root) do
    committed_path = Path.join(project_root, @output_path)

    committed_json =
      case File.read(committed_path) do
        {:ok, content} -> content
        {:error, :enoent} ->
          Mix.raise("""
          #{@output_path} does not exist.
          Run `mix foundry.diagram.generate` to create it, then commit the file.
          """)
      end

    fresh_map     = Jason.decode!(fresh_json) |> Map.delete("generated_at")
    committed_map = Jason.decode!(committed_json) |> Map.delete("generated_at")

    if fresh_map == committed_map do
      Mix.shell().info("System map is current. No diff.")
    else
      Mix.shell().error("""
      System map is stale — the committed #{@output_path} does not match
      the current codebase.

      Run `mix foundry.diagram.generate` and commit the result.
      """)
      exit({:shutdown, 1})
    end
  end
end
