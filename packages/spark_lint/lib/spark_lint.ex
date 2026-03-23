defmodule SparkLint do
  @moduledoc """
  spark_lint — a minimal, zero-dependency lint rule runner for Spark/Ash projects.

  Ships the framework only. Rules ship separately (e.g. as part of Foundry's
  internal `Foundry.LintRules.*` modules, or as third-party Hex packages).

  ## Quick start

      defmodule MyApp.Rules.MissingDoc do
        @behaviour SparkLint.Rule

        @impl SparkLint.Rule
        def check(module, _ctx) do
          case Code.fetch_docs(module) do
            {:docs_v1, _, _, _, :none, _, _} ->
              {:ok, [%SparkLint.Violation{
                rule: :missing_doc,
                module: module,
                message: "\#{inspect(module)} is missing @moduledoc",
                severity: :error
              }]}
            _ ->
              {:ok, []}
          end
        end
      end

      {violations, errors} = SparkLint.run([MyApp.Rules.MissingDoc], modules)
  """

  defdelegate run(rules, modules, base_context \\ %{}), to: SparkLint.Runner
end
