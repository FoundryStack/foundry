defmodule SparkLintTest do
  use ExUnit.Case

  defmodule TestRule do
    @behaviour SparkLint.Rule

    @impl SparkLint.Rule
    def check(module, _ctx) do
      if module == SparkLintTest.TestModule do
        {:ok,
         [
           %SparkLint.Violation{
             rule: :test_rule,
             module: module,
             message: "Test violation",
             severity: :error
           }
         ]}
      else
        {:ok, []}
      end
    end
  end

  defmodule ErrorProducingRule do
    @behaviour SparkLint.Rule

    @impl SparkLint.Rule
    def check(_module, _ctx) do
      {:ok,
       [
         %SparkLint.Violation{
           rule: :error_rule,
           module: SparkLintTest.TestModule,
           message: "Test error violation",
           severity: :error
         }
       ]}
    end
  end

  defmodule CrashingRule do
    @behaviour SparkLint.Rule

    @impl SparkLint.Rule
    def check(_module, _ctx) do
      {:error, "Test error"}
    end
  end

  defmodule WarningRule do
    @behaviour SparkLint.Rule

    @impl SparkLint.Rule
    def check(module, _ctx) do
      {:ok,
       [
         %SparkLint.Violation{
           rule: :warning_rule,
           module: module,
           message: "Test warning",
           severity: :warning
         }
       ]}
    end
  end

  defmodule InfoRule do
    @behaviour SparkLint.Rule

    @impl SparkLint.Rule
    def check(module, _ctx) do
      {:ok,
       [
         %SparkLint.Violation{
           rule: :info_rule,
           module: module,
           message: "Test info",
           severity: :info
         }
       ]}
    end
  end

  defmodule ContextCheckRule do
    @behaviour SparkLint.Rule

    @impl SparkLint.Rule
    def check(_module, ctx) do
      send(self(), {:context_check, module: ctx.module, modules: ctx.modules, metadata: ctx.metadata})
      {:ok, []}
    end
  end

  defmodule TestModule do
  end

  defmodule OtherModule do
  end

  test "run returns violations from rules" do
    {violations, errors} = SparkLint.run([TestRule], [TestModule, OtherModule])

    assert length(violations) == 1
    assert hd(violations).rule == :test_rule
    assert hd(violations).severity == :error
    assert errors == []
  end

  test "run captures rule errors" do
    {violations, errors} = SparkLint.run([CrashingRule], [TestModule])

    assert violations == []
    assert length(errors) == 1
    assert hd(errors).rule == CrashingRule
    assert hd(errors).reason == "Test error"
  end

  test "run sorts violations by severity then module name" do
    {violations, _} = SparkLint.run([ErrorProducingRule, WarningRule, InfoRule], [TestModule])

    # Each rule produces one violation
    severities = Enum.map(violations, & &1.severity)
    assert severities == [:error, :warning, :info]
  end

  test "run with empty rules returns empty violations" do
    {violations, errors} = SparkLint.run([], [TestModule])

    assert violations == []
    assert errors == []
  end

  test "context passes module and modules correctly" do
    SparkLint.run([ContextCheckRule], [TestModule, OtherModule])

    assert_receive {:context_check, [module: TestModule, modules: modules, metadata: %{}]},
                   1000

    assert modules == [TestModule, OtherModule]
  end

  test "metadata is passed through context" do
    SparkLint.run([ContextCheckRule], [TestModule], %{metadata: %{key: :value}})

    assert_receive {:context_check, [module: TestModule, modules: _modules, metadata: metadata]},
                   1000

    assert metadata == %{key: :value}
  end

  test "SparkLint.run delegates to Runner" do
    {v1, e1} = SparkLint.run([TestRule], [TestModule])
    {v2, e2} = SparkLint.Runner.run([TestRule], [TestModule])

    assert v1 == v2
    assert e1 == e2
  end
end
