defmodule Foundry.SparkLintTest do
  use ExUnit.Case, async: true

  defmodule AlwaysPassRule do
    @behaviour SparkLint.Rule
    def check(_module, _ctx), do: {:ok, []}
  end

  defmodule AlwaysViolateRule do
    @behaviour SparkLint.Rule
    def check(module, _ctx) do
      {:ok, [%SparkLint.Violation{
        rule: :test_violation, module: module,
        message: "test", severity: :error
      }]}
    end
  end

  defmodule CrashingRule do
    @behaviour SparkLint.Rule
    def check(_module, _ctx), do: {:error, :rule_crashed}
  end

  test "rule with no violations returns empty list" do
    {violations, errors} = SparkLint.Runner.run([AlwaysPassRule], [String], %{})
    assert violations == [] and errors == []
  end

  test "violation is included in output" do
    {violations, _} = SparkLint.Runner.run([AlwaysViolateRule], [String], %{})
    assert length(violations) == 1
    assert hd(violations).rule == :test_violation
  end

  test "rule error is collected, runner continues" do
    {violations, errors} =
      SparkLint.Runner.run([AlwaysViolateRule, CrashingRule], [String], %{})
    assert length(violations) == 1
    assert length(errors) == 1
  end

  test "violations ordered :error before :warning, alpha by module within severity" do
    defmodule MixedRule do
      @behaviour SparkLint.Rule
      def check(_module, _ctx) do
        {:ok, [
          %SparkLint.Violation{rule: :w, module: Zeta,  message: "", severity: :warning},
          %SparkLint.Violation{rule: :a, module: Alpha, message: "", severity: :error},
          %SparkLint.Violation{rule: :b, module: Beta,  message: "", severity: :error}
        ]}
      end
    end

    {violations, _} = SparkLint.Runner.run([MixedRule], [String], %{})
    severities = Enum.map(violations, & &1.severity)
    assert List.first(severities) == :error
    errors = Enum.filter(violations, & &1.severity == :error)
    mods   = Enum.map(errors, &inspect(&1.module))
    assert mods == Enum.sort(mods)
  end

  test "runner collects all violations before returning" do
    {violations, _} =
      SparkLint.Runner.run([AlwaysViolateRule, AlwaysViolateRule], [String], %{})
    assert length(violations) == 2
  end
end
