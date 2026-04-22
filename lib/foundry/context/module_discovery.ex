defmodule Foundry.Context.ModuleDiscovery do
  @moduledoc """
  Discovers all project modules by scanning the compiled BEAM files.

  This module extracts module discovery logic into a single source of truth,
  used by both GraphBuilder and other context-building tasks.
  """

  @spec all_project_modules(String.t(), String.t()) :: list(atom())
  def all_project_modules(project_root, project_name_string) do
    underscored = Macro.underscore(project_name_string)
    prefix = "Elixir." <> project_name_string <> "."

    # Try dev first, then fall back to test (for subprocess with MIX_ENV=test)
    ebin_path =
      ["dev", "test"]
      |> Enum.map(&Path.join([project_root, "_build", &1, "lib", underscored, "ebin"]))
      |> Enum.find(&File.dir?/1)

    case ebin_path do
      nil ->
        []

      path ->
        Code.append_path(path)
        Path.wildcard(Path.join(path, "*.beam"))
        |> Enum.map(&(&1 |> Path.basename(".beam") |> String.to_atom()))
        |> Enum.filter(&(Atom.to_string(&1) |> String.starts_with?(prefix)))
        |> Enum.filter(&Code.ensure_loaded?/1)
        |> Enum.filter(&is_project_module?/1)
    end
  end

  # Filter out generated modules, domains, and infrastructure
  # Keep user-defined resources, reactors, rules, blueprints, providers, jobs
  defp is_project_module?(module) do
    module_str = Atom.to_string(module)
    clean_name = String.replace(module_str, ~r/^Elixir\./, "")
    part_count = clean_name |> String.split(".") |> Enum.count()

    # Blacklist: modules we definitely don't want
    should_exclude =
      # CLDR-generated modules
      String.contains?(module_str, ".Cldr") or
        # Migration-related and generated version modules
        String.contains?(module_str, ["Migrations", ".Version"]) or
        # Infrastructure modules (but keep .Rules.*)
        (String.contains?(module_str, [".Application", ".Repo", ".Secrets"]) and
           not String.contains?(module_str, [".Rules."])) or
        # Behaviour definitions and base behavior modules (Adapter, Rule)
        String.contains?(module_str, "Adapter") and not String.contains?(module_str, ".Adapters.") or
        module_str == "Elixir.IgamingRef.Rule" or
        # Domain containers have exactly 2 parts (Project.Domain)
        part_count == 2

    not should_exclude
  end
end
