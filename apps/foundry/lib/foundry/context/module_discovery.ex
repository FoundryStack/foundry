defmodule Foundry.Context.ModuleDiscovery do
  @moduledoc """
  Discovers all project modules by scanning the compiled BEAM files.

  This module extracts module discovery logic into a single source of truth,
  used by both GraphBuilder and other context-building tasks.
  """

  @spec all_project_modules(String.t(), String.t()) :: list(atom())
  def all_project_modules(project_root, project_name_string) do
    ebin_path = Path.join([project_root, "_build", "dev", "lib",
                           Macro.underscore(project_name_string), "ebin"])
    prefix    = "Elixir." <> project_name_string <> "."

    Path.wildcard(Path.join(ebin_path, "*.beam"))
    |> Enum.map(&(&1 |> Path.basename(".beam") |> String.to_atom()))
    |> Enum.filter(&(Atom.to_string(&1) |> String.starts_with?(prefix)))
    |> Enum.filter(&Code.ensure_loaded?/1)
  end
end
