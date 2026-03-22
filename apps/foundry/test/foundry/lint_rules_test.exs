defmodule Foundry.LintRulesTest do
  use ExUnit.Case, async: true

  alias Foundry.SparkLint.Context

  describe "Foundry.LintRules.PaperTrailRule" do
    test "returns no violation when module not in sensitive list" do
      ctx = %Context{module: String, modules: [String], metadata: %{sensitive_modules: []}}
      {:ok, violations} = Foundry.LintRules.PaperTrailRule.check(String, ctx)
      assert violations == []
    end

    test "returns violation when module in sensitive list but lacks AshPaperTrail" do
      fixture = Foundry.LintFixtures.MissingPaperTrail
      ctx = %Context{
        module: fixture,
        modules: [fixture],
        metadata: %{sensitive_modules: [fixture]}
      }
      {:ok, violations} = Foundry.LintRules.PaperTrailRule.check(fixture, ctx)
      assert length(violations) == 1
      assert hd(violations).rule == :missing_paper_trail
      assert hd(violations).severity == :error
    end
  end

  describe "Foundry.LintRules.ArchivalRule" do
    test "returns no violation when module not in sensitive list" do
      ctx = %Context{module: String, modules: [String], metadata: %{sensitive_modules: []}}
      {:ok, violations} = Foundry.LintRules.ArchivalRule.check(String, ctx)
      assert violations == []
    end

    test "returns violation when module in sensitive list but lacks AshArchival" do
      fixture = Foundry.LintFixtures.MissingArchival
      ctx = %Context{
        module: fixture,
        modules: [fixture],
        metadata: %{sensitive_modules: [fixture]}
      }
      {:ok, violations} = Foundry.LintRules.ArchivalRule.check(fixture, ctx)
      assert length(violations) == 1
      assert hd(violations).rule == :missing_archival
      assert hd(violations).severity == :error
    end
  end

  describe "Foundry.LintRules.RunbookRule" do
    test "returns no violation for non-reactor modules" do
      ctx = %Context{module: String, modules: [String], metadata: %{project_root: File.cwd!()}}
      {:ok, violations} = Foundry.LintRules.RunbookRule.check(String, ctx)
      assert violations == []
    end

    test "returns no violation for reactor with 3 or fewer steps" do
      fixture = Foundry.LintFixtures.NoRunbookTransfer
      ctx = %Context{
        module: fixture,
        modules: [fixture],
        metadata: %{project_root: File.cwd!()}
      }
      {:ok, violations} = Foundry.LintRules.RunbookRule.check(fixture, ctx)
      # Will return [] because fixture has no steps
      assert violations == []
    end
  end

  describe "Foundry.LintRules.IdempotencyRule" do
    test "returns no violation for non-reactor modules" do
      ctx = %Context{module: String, modules: [String], metadata: %{}}
      {:ok, violations} = Foundry.LintRules.IdempotencyRule.check(String, ctx)
      assert violations == []
    end

    test "returns no violation for reactor with no side effects" do
      fixture = Foundry.LintFixtures.NoIdempotencyTransfer
      ctx = %Context{
        module: fixture,
        modules: [fixture],
        metadata: %{}
      }
      {:ok, violations} = Foundry.LintRules.IdempotencyRule.check(fixture, ctx)
      # Will return [] because fixture has no side-effect steps
      assert violations == []
    end
  end

  describe "Foundry.LintRules.DescriptionRule" do
    test "returns no violation when @moduledoc is present" do
      ctx = %Context{module: String, modules: [String], metadata: %{}}
      {:ok, violations} = Foundry.LintRules.DescriptionRule.check(String, ctx)
      assert violations == []
    end

    test "accepts @moduledoc false as intentionally hidden" do
      fixture = Foundry.LintFixtures.NoModuledoc
      ctx = %Context{module: fixture, modules: [fixture], metadata: %{}}
      {:ok, violations} = Foundry.LintRules.DescriptionRule.check(fixture, ctx)
      # @moduledoc false is acceptable (intentionally hidden)
      assert violations == []
    end
  end

  describe "Foundry.LintRules.VersionRule" do
    test "handles missing mix.lock gracefully" do
      ctx = %Context{
        module: String,
        modules: [String],
        metadata: %{project_root: "/nonexistent/path"}
      }
      {:ok, violations} = Foundry.LintRules.VersionRule.check(String, ctx)
      # Should not crash, returns empty list or violations
      assert is_list(violations)
    end
  end

  describe "Foundry.LintRules.AdapterVersionRule" do
    test "returns no violations in phase 1" do
      ctx = %Context{module: String, modules: [String], metadata: %{}}
      {:ok, violations} = Foundry.LintRules.AdapterVersionRule.check(String, ctx)
      assert violations == []
    end
  end

  describe "Foundry.LintRules.ManifestValidator" do
    test "returns no violation when required approvers are present" do
      manifest = [
        approvers: [sensitive_lead: "alice@example.com", compliance_officer: "bob@example.com"]
      ]
      violations = Foundry.LintRules.ManifestValidator.check(manifest)
      # Filter to only approver violations
      approver_violations = Enum.filter(violations, &(&1.rule == :manifest_missing_required_approver))
      assert approver_violations == []
    end

    test "returns violations when required approvers are missing" do
      manifest = [approvers: []]
      violations = Foundry.LintRules.ManifestValidator.check(manifest)
      approver_violations = Enum.filter(violations, &(&1.rule == :manifest_missing_required_approver))
      assert length(approver_violations) == 2
      Enum.each(approver_violations, fn v ->
        assert v.severity == :error
      end)
    end

    test "returns no violation when coverage weights sum to 1.0" do
      manifest = [
        coverage_weights: [
          transfer_coverage: 0.25,
          rule_coverage: 0.25,
          blueprint_coverage: 0.25,
          compliance_coverage: 0.25,
          ui_coverage: 0.0
        ]
      ]
      violations = Foundry.LintRules.ManifestValidator.check(manifest)
      weight_violations = Enum.filter(violations, &(&1.rule == :manifest_invalid_coverage_weights))
      assert weight_violations == []
    end

    test "returns violation when coverage weights don't sum to 1.0" do
      manifest = [
        coverage_weights: [
          transfer_coverage: 0.2,
          rule_coverage: 0.2,
          blueprint_coverage: 0.2,
          compliance_coverage: 0.2,
          ui_coverage: 0.1
        ]
      ]
      violations = Foundry.LintRules.ManifestValidator.check(manifest)
      weight_violations = Enum.filter(violations, &(&1.rule == :manifest_invalid_coverage_weights))
      assert length(weight_violations) == 1
      assert hd(weight_violations).severity == :error
    end

    test "returns violation when exemption references unknown sensitive resource" do
      manifest = [
        sensitive_resources: [TestApp.Resource1],
        sensitive_resource_exemptions: [TestApp.Resource2]
      ]
      violations = Foundry.LintRules.ManifestValidator.check(manifest)
      exemption_violations = Enum.filter(violations, &(&1.rule == :manifest_unknown_sensitive_resource))
      assert length(exemption_violations) == 1
      assert hd(exemption_violations).severity == :error
    end
  end

  describe "Foundry.LintRules.Registry" do
    test "module_rules returns all registered rules" do
      rules = Foundry.LintRules.Registry.module_rules()
      assert is_list(rules)
      assert length(rules) == 7
      assert Foundry.LintRules.PaperTrailRule in rules
      assert Foundry.LintRules.ArchivalRule in rules
      assert Foundry.LintRules.RunbookRule in rules
      assert Foundry.LintRules.IdempotencyRule in rules
      assert Foundry.LintRules.DescriptionRule in rules
      assert Foundry.LintRules.VersionRule in rules
      assert Foundry.LintRules.AdapterVersionRule in rules
    end

    test "manifest_validators returns ManifestValidator" do
      validators = Foundry.LintRules.Registry.manifest_validators()
      assert validators == [Foundry.LintRules.ManifestValidator]
    end
  end
end
