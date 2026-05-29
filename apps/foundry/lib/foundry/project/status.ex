defmodule Foundry.Project.Status do
  @moduledoc """
  Ash resource wrapping the output of `mix foundry.project.status`.

  Represents the health summary of a target project: lint state, migration
  status, open proposals, compliance gaps, and stack versions.

  Delegates to `Foundry.Status.build/1` for the actual data.
  """

  use Ash.Resource,
    domain: Foundry.Context,
    data_layer: Ash.DataLayer.Simple,
    extensions: [AshJsonApi.Resource]

  json_api do
    type "project_status"
  end

  attributes do
    uuid_primary_key :id

    attribute :project, :string do
      description("Project name from the manifest.")
      allow_nil?(false)
    end

    attribute :project_type, :string do
      description("Project type from the manifest (e.g. 'standard', 'umbrella').")
      allow_nil?(false)
    end

    attribute :domain_type, :string do
      description("Domain type declared in the manifest.")
      allow_nil?(false)
    end

    attribute :domains, {:array, :string} do
      description("List of domain names discovered in the project.")
      default([])
    end

    attribute :sensitive_modules, {:array, :string} do
      description("Modules marked as sensitive in the manifest.")
      default([])
    end

    attribute :lint_errors, :integer do
      description("Count of lint errors.")
      default(0)
    end

    attribute :lint_warnings, :integer do
      description("Count of lint warnings.")
      default(0)
    end

    attribute :pending_migrations, :integer do
      description("Count of pending migrations.")
      default(0)
    end

    attribute :open_proposals, :integer do
      description("Count of open proposals.")
      default(0)
    end

    attribute :compliance_total, :integer do
      description("Total number of compliance requirements.")
      default(0)
    end

    attribute :compliance_covered, :integer do
      description("Number of compliance requirements with test coverage.")
      default(0)
    end

    attribute :stack_versions, :map do
      description("Map of dependency name to version string from mix.lock.")
      default(%{})
    end

    attribute :compiled_at, :utc_datetime do
      description("Timestamp of the most recent .beam file compilation.")
      allow_nil?(true)
    end

    attribute :generated_at, :utc_datetime do
      description("When this status snapshot was generated.")
      allow_nil?(false)
    end
  end

  actions do
    read :read do
      primary? true

      prepare fn query, _ ->
        project_root = query.context[:project_root] || File.cwd!()

        case build_status(project_root) do
          {:ok, status_map} ->
            data = Map.merge(%{"id" => Ash.UUIDv7.generate()}, status_map)
            record = struct(__MODULE__, atomize_keys(data))
            Ash.DataLayer.Simple.set_data(query, [record])

          {:error, reason} ->
            Ash.Query.add_error(query, reason)
        end
      end
    end
  end

  defp build_status(project_root) do
    try do
      status = Foundry.Status.build(project_root)

      {:ok, %{
        "project" => status["project"],
        "project_type" => status["project_type"],
        "domain_type" => status["domain_type"],
        "domains" => status["domains"] || [],
        "sensitive_modules" => status["sensitive_modules"] || [],
        "lint_errors" => get_in(status, ["lint", "error_count"]) || 0,
        "lint_warnings" => get_in(status, ["lint", "warning_count"]) || 0,
        "pending_migrations" => get_in(status, ["migrations", "count"]) || 0,
        "open_proposals" => get_in(status, ["proposals", "count"]) || 0,
        "compliance_total" => get_in(status, ["compliance", "total"]) || 0,
        "compliance_covered" => get_in(status, ["compliance", "covered"]) || 0,
        "stack_versions" => status["stack"] || %{},
        "compiled_at" => parse_datetime(status["compiled_at"]),
        "generated_at" => parse_datetime(status["generated_at"]) || DateTime.utc_now()
      }}
    catch
      kind, error -> {:error, Exception.format(kind, error, __STACKTRACE__)}
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(iso_str) when is_binary(iso_str) do
    case DateTime.from_iso8601(iso_str) do
      {:ok, dt, _} -> dt
      {:error, _} -> nil
    end
  end
  defp parse_datetime(dt), do: dt

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end
end
