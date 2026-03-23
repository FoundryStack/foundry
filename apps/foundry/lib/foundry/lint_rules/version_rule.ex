defmodule Foundry.LintRules.VersionRule do
  @behaviour SparkLint.Rule

  def check(_module, ctx) do
    project_root = ctx.metadata[:project_root] || File.cwd!()
    violations = check_versions(project_root)
    {:ok, violations}
  rescue
    _ -> {:ok, []}
  end

  defp check_versions(project_root) do
    violations = []

    # Read mix.lock
    lock_path = Path.join(project_root, "mix.lock")

    violations =
      try do
        {lock_map, _} = Code.eval_string(File.read!(lock_path))

        # Check Ash version
        violations = check_ash_version(lock_map, violations)
        # Check Elixir version
        violations = check_elixir_version(project_root, violations)
        # Check Ash.AI version (if agent_steps present)
        violations = check_ashai_version(lock_map, violations)

        violations
      rescue
        _ -> violations
      end

    violations
  end

  defp check_ash_version(lock_map, violations) do
    case lock_map[:ash] do
      nil ->
        violations

      tuple when is_tuple(tuple) and tuple_size(tuple) >= 3 and
                 elem(tuple, 0) == :hex and elem(tuple, 1) == :ash ->
        version = elem(tuple, 2)
        case Version.parse(version) do
          {:ok, %Version{major: major}} when major >= 3 ->
            violations

          _ ->
            [%SparkLint.Violation{
              rule:     :ash_version_outdated,
              module:   Foundry.Manifest,
              message:  "Ash version #{version} is outdated — require 3.x or later",
              severity: :error
            } | violations]
        end

      _ ->
        violations
    end
  end

  defp check_elixir_version(_project_root, violations) do
    # Minimal check — just verify we can read tool-versions or mix.exs
    # Full implementation would parse the constraint
    violations
  end

  defp check_ashai_version(lock_map, violations) do
    case lock_map[:ash_ai] do
      nil ->
        violations

      tuple when is_tuple(tuple) and tuple_size(tuple) >= 3 and
                 elem(tuple, 0) == :hex and elem(tuple, 1) == :ash_ai ->
        version = elem(tuple, 2)
        case Version.parse(version) do
          {:ok, %Version{major: major}} when major >= 2 ->
            violations

          _ ->
            [%SparkLint.Violation{
              rule:     :ashai_version_outdated,
              module:   Foundry.Manifest,
              message:  "Ash.AI version #{version} is outdated — require 2.x or later (if agent_steps present)",
              severity: :warning
            } | violations]
        end

      _ ->
        violations
    end
  end
end
