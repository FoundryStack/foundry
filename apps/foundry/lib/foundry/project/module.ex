defmodule Foundry.Project.Module do
  @moduledoc """
  Ash resource wrapping the output of `mix foundry.context <Module>`.

  Represents a single module's context: its type, domain, relationships,
  compliance links, test coverage, and agent step declarations.

  Delegates to `Foundry.Context.ProjectContext.build_one/2` for single-module
  lookups and `Foundry.Context.GraphBuilder.build/2` for full enumeration.
  """

  use Ash.Resource,
    domain: Foundry.Context,
    data_layer: Ash.DataLayer.Simple

  attributes do
    attribute :id, :string do
      description("Fully qualified module name (e.g. 'MyApp.Finance.Wallet').")
      primary_key?(true)
      allow_nil?(false)
    end

    attribute :module, :string do
      description("Fully qualified module name, same as id.")
      allow_nil?(false)
    end

    attribute :type, :atom do
      description("Module type: :resource, :transfer, :rule, :blueprint, :adapter, :live_page, :oban_job.")
      allow_nil?(false)
    end

    attribute :domain, :string do
      description("Parent domain name.")
      allow_nil?(false)
    end

    attribute :app, :string do
      description("App name (for umbrella projects).")
      allow_nil?(true)
    end

    attribute :description, :string do
      description("First paragraph of @moduledoc.")
      allow_nil?(true)
    end

    attribute :sensitive, :boolean do
      description("Whether this module is declared as sensitive in the manifest.")
      default(false)
    end

    attribute :rules, {:array, :string} do
      description("Rule module names applied to this module.")
      default([])
    end

    attribute :compliance, {:array, :string} do
      description("RG-* requirement IDs linked in this module.")
      default([])
    end

    attribute :adrs, {:array, :string} do
      description("ADR IDs referenced in the @moduledoc.")
      default([])
    end

    attribute :runbook, :string do
      description("Path to the runbook file, if one exists.")
      allow_nil?(true)
    end

    attribute :data_layer, :string do
      description("Data layer string (e.g. 'ash_postgres', 'ash_ets').")
      allow_nil?(true)
    end

    attribute :pending_migrations, :boolean do
      description("Whether this module has pending migrations.")
      default(false)
    end

    attribute :paper_trail, :boolean do
      description("Whether AshPaperTrail is enabled.")
      default(false)
    end

    attribute :archival, :boolean do
      description("Whether AshArchival is enabled.")
      default(false)
    end

    attribute :test_coverage, :map do
      description("Test coverage map: %{property_tests, scenario_tests, e2e_tests}.")
      default(%{})
    end

    attribute :state_machine, :map do
      description("State machine metadata if present.")
      default(%{})
    end

    attribute :agent_steps, {:array, :map} do
      description("Agent step declarations for modules with AshAI integration.")
      default([])
    end

    attribute :telemetry_prefix, {:array, :string} do
      description("Telemetry prefix segments.")
      default([])
    end

    attribute :last_modified, :string do
      description("ISO 8601 date of last modification.")
      allow_nil?(true)
    end
  end

  actions do
    read :read do
      primary? true

      prepare fn query, _ ->
        project_root = query.context[:project_root] || File.cwd!()
        module_filter = query.filter[Access.key(:id)]

        with {:ok, record_maps} <- build_modules(project_root, module_filter) do
          records = Enum.map(record_maps, &struct(__MODULE__, atomize_keys(&1)))
          Ash.DataLayer.Simple.set_data(query, records)
        else
          {:error, _} = error -> error
        end
      end
    end
  end

  defp build_modules(project_root, module_filter) do
    if module_filter do
      with {:ok, json} <- Mix.Tasks.Foundry.Project.Context.run_single(module_filter, project_root),
           {:ok, decoded} <- Jason.decode(json) do
        {:ok, [module_map_to_record(decoded)]}
      else
        {:error, :module_not_found} -> {:ok, []}
        {:error, _} = error -> error
      end
    else
      {nodes, _edges} = Foundry.Context.GraphBuilder.build(project_root, nil)
      records = Enum.map(nodes, &module_map_to_record/1)
      {:ok, records}
    end
  catch
    kind, error -> {:error, Exception.format(kind, error, __STACKTRACE__)}
  end

  defp module_map_to_record(map) when is_map(map) do
    %{
      "id" => map["id"] || map["module"],
      "module" => map["module"],
      "type" => String.to_atom(map["type"] || "unknown"),
      "domain" => map["domain"],
      "app" => map["app"],
      "description" => map["description"],
      "sensitive" => map["sensitive"] || false,
      "rules" => map["rules"] || [],
      "compliance" => map["compliance"] || [],
      "adrs" => map["adrs"] || [],
      "runbook" => map["runbook"],
      "data_layer" => map["data_layer"],
      "pending_migrations" => map["pending_migrations"] || false,
      "paper_trail" => map["paper_trail"] || false,
      "archival" => map["archival"] || false,
      "test_coverage" => map["test_coverage"] || %{},
      "state_machine" => map["state_machine"] || %{},
      "agent_steps" => map["agent_steps"] || [],
      "telemetry_prefix" => map["telemetry_prefix"] || [],
      "last_modified" => map["last_modified"]
    }
  end

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end
end
