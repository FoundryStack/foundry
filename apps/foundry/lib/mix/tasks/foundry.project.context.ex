defmodule Mix.Tasks.Foundry.Project.Context do
  use Mix.Task
  @shortdoc "Generate or query the project context"

  @moduledoc """
  Generates project context for Foundry modules.

  ## Usage

      mix foundry.project.context <Module>         # Per-module context
      mix foundry.project.context <Module> --json  # Same (--json accepted, output is always JSON)
      mix foundry.project.context                  # Bulk project context
      mix foundry.project.context --check          # Check lock freshness

  ## Options

  - `--json` - Accepted for agent compatibility; output is always JSON regardless of this flag.
  - `--check` - Check if context.lock is current instead of generating context.

  ## Forms

  - `mix foundry.project.context <Module>`: Returns JSON context for a single module
  - `mix foundry.project.context`: Returns bulk context for all modules in project
  - `mix foundry.project.context --check`: Checks if mix.lock is current
  """

  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [json: :boolean, check: :boolean])

    cond do
      Keyword.get(opts, :check, false) ->
        run_check(File.cwd!())

      rest == [] ->
        Mix.Task.run("compile")
        run_bulk(File.cwd!())

      match?([_], rest) ->
        Mix.Task.run("compile")
        run_single(hd(rest), File.cwd!())

      true ->
        Mix.raise("Usage: mix foundry.project.context [<Module> | --check] [--json]")
    end
  end

  @doc """
  Emit JSON context for a single module. Separated from `run/1` so tests can
  call this without triggering Mix.Task.run("compile") / Mix.Sync.PubSub startup.
  Returns `{:ok, json_string}` or `{:error, reason}`.
  """
  def run_single(module_name, project_root) do
    with {:ok, manifest} <- Foundry.Manifest.Parser.read(project_root),
         {:ok, pending_set} <- Foundry.Context.PendingMigrations.check(project_root),
         {:ok, module} <- resolve_module(module_name) do
      info = Foundry.SparkMeta.walk(module)
      pending = Foundry.Context.PendingMigrations.pending?(module, pending_set)
      node = Foundry.Context.NodeBuilder.build(info, manifest, pending)
      json = Jason.encode!(node, pretty: true)
      IO.puts(json)
      {:ok, json}
    else
      {:error, :module_not_found} ->
        payload = Jason.encode!(%{error: "module_not_found", module: module_name})
        IO.puts(payload)
        {:error, :module_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Emit bulk JSON context for all modules. Separated from `run/1` so tests can
  call this without triggering Mix.Task.run("compile") / Mix.Sync.PubSub startup.
  Returns `{:ok, json_string}`.
  """
  def run_bulk(project_root) do
    json =
      Foundry.Context.ProjectMap.build_all(project_root)
      |> Jason.encode!(pretty: true)

    IO.puts(json)
    Foundry.Context.LockFile.write(project_root)
    {:ok, json}
  end

  @doc """
  Check if context.lock is current. Returns `:ok` or `{:error, reason}`.
  """
  def run_check(project_root) do
    case Foundry.Context.LockFile.check(project_root) do
      :ok ->
        IO.puts("context.lock is current.")
        :ok

      {:error, :missing} = err ->
        IO.puts(:stderr, "error: .foundry/context.lock absent. Run: mix foundry.project.context")
        err

      {:error, :stale} = err ->
        IO.puts(:stderr, "error: context.lock is stale. Run: mix foundry.project.context")
        err
    end
  end

  defp resolve_module(module_name) do
    mod = String.to_existing_atom("Elixir." <> module_name)

    if Code.ensure_loaded?(mod) do
      {:ok, mod}
    else
      {:error, :module_not_found}
    end
  rescue
    ArgumentError -> {:error, :module_not_found}
  end
end
