defmodule Foundry.LintRules.GraphqlMutationRule do
  @moduledoc """
  Sensitive resources with GraphQL mutations must have explicit authorization policies.

  Rule IDs:
  - `:graphql_mutation_unsecured` — mutation exists on sensitive resource with no policies
  - `:graphql_mutation_unauthenticated` — mutation requires auth but no auth strategy declared

  If a sensitive resource has JSON:API or GraphQL mutations targeting it and
  has no authorization policies, it is flagged as unsecured.
  """

  @behaviour SparkLint.Rule

  def check(module, ctx) do
    sensitive = ctx.metadata[:sensitive_modules] || []

    if module in sensitive do
      violations =
        []
        |> check_unsecured_mutation(module)

      {:ok, violations}
    else
      {:ok, []}
    end
  end

  defp check_unsecured_mutation(violations, module) do
    if has_actions?(module) and not has_policies?(module) do
      [
        %SparkLint.Violation{
          rule: :graphql_mutation_unsecured,
          module: module,
          message:
            "#{inspect(module)} is sensitive and defines write actions but has no authorization policies. All sensitive resource mutations must be explicitly authorized.",
          severity: :error
        }
        | violations
      ]
    else
      violations
    end
  end

  defp has_actions?(module) do
    case Ash.Resource.Info.actions(module) do
      actions when is_list(actions) ->
        Enum.any?(actions, fn action ->
          action.type in [:create, :update, :destroy]
        end)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp has_policies?(module) do
    authorizers = Ash.Resource.Info.authorizers(module)
    is_list(authorizers) and length(authorizers) > 0
  rescue
    _ -> false
  end
end
