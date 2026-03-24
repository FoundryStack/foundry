defmodule Foundry.Context.ProjectContext do
  @moduledoc """
  Provides convenient access to project context (nodes, edges) without running mix tasks.

  Used by LiveView and other runtime contexts to build or fetch project graphs.
  """

  @doc """
  Builds the complete project context from a project root directory.

  Returns `{:ok, context_map}` or `{:error, reason}`.

  The context_map includes:
  - nodes: list of NodeEntry structs
  - edges: list of EdgeEntry structs
  - generated_at: timestamp
  - project, project_type, domain_type: manifest data
  - spec_kit: spec-kit index
  """
  def build(project_root) do
    try do
      case Foundry.Manifest.Parser.read(project_root) do
        {:ok, manifest} ->
          {nodes, edges} = Foundry.Context.GraphBuilder.build(project_root, manifest)
          spec_kit = Foundry.Context.SpecKitIndexBuilder.build(project_root)

          context = %{
            generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            project: Keyword.get(manifest, :project_name, ""),
            project_type: Keyword.get(manifest, :project_type, "standard"),
            domain_type: Keyword.get(manifest, :domain_type, ""),
            nodes: nodes,
            edges: edges,
            spec_kit: spec_kit
          }

          {:ok, context}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Builds a single node by module ID from a project root.

  Returns `{:ok, NodeEntry}` or `{:error, reason}`.
  """
  def build_one(project_root, module_id) when is_binary(module_id) do
    try do
      case Foundry.Manifest.Parser.read(project_root) do
        {:ok, manifest} ->
          module =
            try do
              String.to_existing_atom("Elixir." <> module_id)
            rescue
              _ -> raise "Module not found: #{module_id}"
            end

          unless Code.ensure_loaded?(module) do
            raise "Module not found: #{module_id}"
          end

          {:ok, pending_set} = Foundry.Context.PendingMigrations.check(project_root)

          info = Foundry.SparkMeta.walk(module)
          pending = Foundry.Context.PendingMigrations.pending?(module, pending_set)
          node = Foundry.Context.NodeBuilder.build(info, manifest, pending)

          {:ok, node}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end
end
