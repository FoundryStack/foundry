defmodule Foundry.Verifiers.SensitiveResourceRequiresPaperTrail do
  @moduledoc """
  Spark compile-time verifier: any Ash.Resource listed in manifest.sensitive_resources
  must use AshPaperTrail.Resource.

  Registered in the Foundry Spark DSL extension so it fires when the target project
  compiles. Violations surface as compile errors before any proposal is created.
  Mirrors SparkLint.Rules.PaperTrailRule but runs at compile time, not proposal submit.
  """

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
    project_root = Application.get_env(:foundry, :current_project_root, File.cwd!())

    case Foundry.Manifest.Parser.read(project_root) do
      {:ok, manifest} ->
        sensitive_resources =
          manifest
          |> Keyword.get(:sensitive_resources, [])
          |> Enum.map(&to_string/1)

        if to_string(module) in sensitive_resources and not uses_paper_trail?(module) do
          {:error,
           Spark.Error.DslError.exception(
             message:
               "#{inspect(module)} is in manifest.sensitive_resources but does not use AshPaperTrail.Resource. " <>
                 "Add `use AshPaperTrail.Resource` or remove it from sensitive_resources (INV-011).",
             module: module
           )}
        else
          :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp uses_paper_trail?(module) do
    extensions = Spark.extensions(module)
    AshPaperTrail.Resource in extensions
  rescue
    _ -> false
  end
end
