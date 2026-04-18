defmodule Mix.Tasks.Foundry.Project.Context do
  use Mix.Task
  @shortdoc "Generate or query the project context"

  @moduledoc """
  Generates project context for Foundry modules.

  ## Usage

      mix foundry.project.context <Module>  # Per-module context
      mix foundry.project.context            # Bulk project context
      mix foundry.project.context --check    # Check lock freshness

  ## Forms

  - `mix foundry.project.context <Module>`: Returns JSON context for a single module
  - `mix foundry.project.context`: Returns bulk context for all modules in project
  - `mix foundry.project.context --check`: Checks if mix.lock is current
  """

  def run(["--check"]),                          do: run_check()
  def run([module_name]) when is_binary(module_name), do: run_single(module_name)
  def run([]),                                   do: run_bulk()
  def run(_), do: Mix.raise("Usage: mix foundry.project.context [<Module> | --check]")

  defp run_single(module_name) do
    Mix.Task.run("app.start")
    project_root = File.cwd!()
    {:ok, manifest}    = Foundry.Manifest.Parser.read(project_root)
    {:ok, pending_set} = Foundry.Context.PendingMigrations.check(project_root)

    module =
      try do String.to_existing_atom("Elixir." <> module_name)
      rescue _ -> emit_error_and_halt("module_not_found", module_name)
      end

    unless Code.ensure_loaded?(module) do
      emit_error_and_halt("module_not_found", module_name)
    end

    info    = Foundry.SparkMeta.walk(module)
    pending = Foundry.Context.PendingMigrations.pending?(module, pending_set)
    node    = Foundry.Context.NodeBuilder.build(info, manifest, pending)

    IO.puts(Jason.encode!(node, pretty: true))
  end

  defp emit_error_and_halt(error, module_name) do
    IO.puts(Jason.encode!(%{error: error, module: module_name}))
    exit({:shutdown, 1})
  end

  defp run_bulk() do
    Mix.Task.run("app.start")
    project_root = File.cwd!()
    {:ok, manifest} = Foundry.Manifest.Parser.read(project_root)

    # Build the complete project graph
    {nodes, edges} = Foundry.Context.GraphBuilder.build(project_root, manifest)

    # Build spec-kit index
    spec_kit = Foundry.Context.SpecKitIndexBuilder.build(project_root)

    # Assemble the bulk context output
    context =
      %{
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        project: Keyword.get(manifest, :project_name, ""),
        project_type: Keyword.get(manifest, :project_type, "standard"),
        nodes: nodes,
        edges: edges,
        spec_kit: spec_kit
      }
      |> then(fn m ->
        case Keyword.get(manifest, :domain_type, "") do
          "" -> m
          dt -> Map.put(m, :domain_type, dt)
        end
      end)

    json_str = Jason.encode!(context, pretty: true)

    clean_json = sanitize_json_string(json_str)
    IO.puts(clean_json)

    # Write lock file for --check to use
    Foundry.Context.LockFile.write(project_root)
  end

  defp run_check() do
    project_root = File.cwd!()
    case Foundry.Context.LockFile.check(project_root) do
      :ok ->
        IO.puts("context.lock is current.")
      {:error, :missing} ->
        IO.puts(:stderr, "error: .foundry/context.lock absent. Run: mix foundry.project.context")
        exit({:shutdown, 1})
      {:error, :stale} ->
        IO.puts(:stderr, "error: context.lock is stale. Run: mix foundry.project.context")
        exit({:shutdown, 1})
    end
  end

  defp sanitize_json_string(json_str) do
    # Replace all Elixir escape sequences (\x{...}) with safe equivalents
    Regex.replace(~r/\\x\{([0-9a-f]+)\}/, json_str, fn _match, code ->
      code
      |> String.to_integer(16)
      |> case do
        0x2014 -> "-"
        0x2013 -> "-"
        0x00D7 -> "*"
        0x201C -> "\""
        0x201D -> "\""
        0x2018 -> "'"
        0x2019 -> "'"
        0x2026 -> "..."
        unicode -> "#{<<unicode::utf8>>}"
      end
    end)
  end
end
