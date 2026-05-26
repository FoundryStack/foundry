defmodule Foundry.Context.ModuleDiscoveryTest do
  use ExUnit.Case, async: true

  alias Foundry.Context.ModuleDiscovery

  # Points at the reference project that is compiled in _build/dev in this repo.
  @ref_root __DIR__
             |> Path.split()
             |> Enum.take_while(&(&1 != "apps"))
             |> Path.join()
             |> Path.join("reference_projects/igaming")

  describe "all_project_modules/2" do
    test "returns a non-empty list of project modules for a compiled project" do
      modules = ModuleDiscovery.all_project_modules(@ref_root, "IgamingRef")
      assert length(modules) > 0, "expected at least one module but got 0 — check :code.load_abs path"
    end

    test "all returned modules are atoms beginning with the project prefix" do
      modules = ModuleDiscovery.all_project_modules(@ref_root, "IgamingRef")
      for mod <- modules do
        assert mod |> Atom.to_string() |> String.starts_with?("Elixir.IgamingRef."),
               "#{mod} does not start with Elixir.IgamingRef."
      end
    end

    test "modules are loadable — not just atoms (catches :embedded false-negative)" do
      modules = ModuleDiscovery.all_project_modules(@ref_root, "IgamingRef")
      # Every returned module must actually be loaded into the VM
      for mod <- modules do
        assert :erlang.module_loaded(mod),
               "#{mod} was returned but is not loaded in the VM"
      end
    end

    test "returns [] for a path where _build does not exist" do
      assert ModuleDiscovery.all_project_modules("/tmp/nonexistent_project_xyzzy", "IgamingRef") == []
    end

    test "returns [] for an unknown project name" do
      assert ModuleDiscovery.all_project_modules(@ref_root, "NoSuchProject") == []
    end
  end
end
