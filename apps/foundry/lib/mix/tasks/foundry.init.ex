defmodule Mix.Tasks.Foundry.Init do
  @moduledoc """
  Initialize a new Foundry project by scaffolding required directories and files.

  Usage:
    mix foundry.init [target_directory]

  If no target directory is provided, the current directory is used.
  """

  use Mix.Task

  def run(args) do
    target_dir = List.first(args) || File.cwd!()
    normalized_target = target_dir |> String.trim() |> Path.expand()

    unless File.dir?(normalized_target) do
      Mix.raise("Target directory does not exist: #{normalized_target}")
    end

    scaffold_foundry_project(normalized_target)
  end

  defp scaffold_foundry_project(target) do
    source_root = source_root()

    Mix.shell().info("[:] Scaffolding Foundry project in #{target}")

    scaffold_agents(source_root, target)
    scaffold_specify(source_root, target)
    scaffold_foundry_manifest(target)
    scaffold_docs_directories(target)
    scaffold_agents_md(source_root, target)
    scaffold_gitignore(source_root, target)

    Mix.shell().info("[:] Foundry project initialized successfully!")
  end

  defp scaffold_agents(source_root, target) do
    source_agents = Path.join(source_root, ".agents/skills")
    target_agents = Path.join(target, ".agents/skills")

    if File.exists?(source_agents) and not File.exists?(target_agents) do
      Mix.shell().info("  [:] Copying agent skills...")
      File.mkdir_p!(Path.dirname(target_agents))
      copy_recursive!(source_agents, target_agents)
    end
  end

  defp scaffold_specify(source_root, target) do
    source_specify = Path.join(source_root, ".specify")
    target_specify = Path.join(target, ".specify")

    if File.exists?(source_specify) and not File.exists?(target_specify) do
      Mix.shell().info("  [:] Copying specification templates...")
      File.mkdir_p!(target_specify)
      copy_recursive!(source_specify, target_specify)
    end
  end

  defp scaffold_foundry_manifest(target) do
    manifest_dir = Path.join(target, ".foundry")
    manifest_file = Path.join(manifest_dir, "manifest.exs")

    unless File.exists?(manifest_file) do
      Mix.shell().info("  [:] Creating foundry manifest...")
      File.mkdir_p!(manifest_dir)

      project_name = Path.basename(target)

      manifest_content = """
      # Foundry Project Manifest
      # Auto-generated: #{DateTime.utc_now()}

      %{
        name: "#{project_name}",
        description: "A Foundry project",
        version: "0.0.1",
        domains: [],
        agent_skills: ["thinking", "chat", "research"],
        integrations: []
      }
      """

      File.write!(manifest_file, manifest_content)
    end
  end

  defp scaffold_docs_directories(target) do
    dirs = ["docs/adrs", "docs/runbooks", "docs/regulations"]

    Enum.each(dirs, fn dir ->
      full_path = Path.join(target, dir)
      unless File.dir?(full_path) do
        File.mkdir_p!(full_path)
      end
    end)

    Mix.shell().info("  [:] Created documentation directories...")
  end

  defp scaffold_agents_md(source_root, target) do
    source_agents_md = Path.join(source_root, "AGENTS.md")
    target_agents_md = Path.join(target, "AGENTS.md")

    if File.exists?(source_agents_md) and not File.exists?(target_agents_md) do
      Mix.shell().info("  [:] Copying AGENTS.md...")
      File.cp!(source_agents_md, target_agents_md)
    end
  end

  defp scaffold_gitignore(source_root, target) do
    source_gitignore = Path.join(source_root, "reference_projects/igaming/.gitignore")
    target_gitignore = Path.join(target, ".gitignore")

    if File.exists?(source_gitignore) and not File.exists?(target_gitignore) do
      Mix.shell().info("  [:] Copying .gitignore...")
      File.cp!(source_gitignore, target_gitignore)
    end
  end

  defp source_root do
    # Try environment variable first
    case System.get_env("FOUNDRY_SOURCE_ROOT") do
      nil ->
        # Try application dir
        case Application.app_dir(:foundry, "priv/scaffold") do
          path when is_binary(path) and path != "" -> path
          _ -> derive_source_root()
        end

      env_root ->
        env_root
    end
  end

  defp derive_source_root do
    # Go up 5 levels from lib/mix/tasks to repo root
    __DIR__
    |> Path.split()
    |> Enum.take(length(Path.split(__DIR__)) - 5)
    |> Path.join()
  end

  defp copy_recursive!(source, target) do
    File.cp_r!(source, target)
  end
end
