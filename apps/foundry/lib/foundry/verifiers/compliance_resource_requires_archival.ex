defmodule Foundry.Verifiers.ComplianceResourceRequiresArchival do
  @moduledoc """
  Spark compile-time verifier: any Ash.Resource referenced in manifest.compliance_requirements
  must use AshArchival.Resource.

  Mirrors SparkLint.Rules.ArchivalRule but runs at compile time.
  """

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
    project_root = Application.get_env(:foundry, :current_project_root, File.cwd!())

    case Foundry.Manifest.Parser.read(project_root) do
      {:ok, manifest} ->
        compliance_modules =
          manifest
          |> Keyword.get(:compliance_requirements, [])
          |> Enum.flat_map(fn req ->
            List.wrap(req[:implementing_modules] || req["implementing_modules"] || [])
          end)
          |> Enum.map(&to_string/1)

        if to_string(module) in compliance_modules and not uses_archival?(module) do
          {:error,
           Spark.Error.DslError.exception(
             message:
               "#{inspect(module)} implements a compliance requirement but does not use AshArchival.Resource. " <>
                 "Add `use AshArchival.Resource` to enable soft-delete archival (INV-012).",
             module: module
           )}
        else
          :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp uses_archival?(module) do
    extensions = Spark.extensions(module)
    AshArchival.Resource in extensions
  rescue
    _ -> false
  end
end
