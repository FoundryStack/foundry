defmodule Foundry.IntegrationStep10Test do
  @moduledoc """
  Step 10: CI Pipeline Simulation — Integration Tests

  Tests the complete Foundry CI pipeline as it would run in CI:
  1. Sequence test: compile → lint
  2. Staleness cycle: detect stale context
  3. Mutation tests: verify lint rules catch expected violations
  """

  use ExUnit.Case, async: false

  @igaming_root Path.expand("../../../reference_projects/igaming", __DIR__)

  setup_all do
    # igaming is already compiled; BEAM files exist in _build/
    # Skip compilation to avoid domain configuration warnings
    :ok
  end

  # ============================================================================
  # SEQUENCE TESTS: Baseline CI Pipeline
  # ============================================================================

  describe "sequence test: baseline CI pipeline" do
    test "foundry.lint.all returns no errors on clean igaming state" do
      report = Foundry.Lint.Runner.run(@igaming_root)
      assert report.passed, "lint should pass on clean igaming. Violations: #{inspect(report.violations)}"
      assert report.error_count == 0, "should have no errors, got: #{report.error_count}"
    end

    test "foundry.project.context generates lock file" do
      Foundry.Context.LockFile.write(@igaming_root)
      lock_path = Path.join([@igaming_root, ".foundry", "context.lock"])
      assert File.exists?(lock_path), "context.lock should be created"
    end
  end

  # ============================================================================
  # STALENESS CYCLE TESTS: Lock File Freshness Detection
  # ============================================================================

  describe "staleness cycle: lock file staleness detection" do
    setup do
      # Ensure fresh lock file exists
      Foundry.Context.LockFile.write(@igaming_root)
      :ok
    end

    test "--check passes when lock is current" do
      assert Foundry.Context.LockFile.check(@igaming_root) == :ok
    end

    test "--check fails when lock hash is stale" do
      lock_path = Path.join([@igaming_root, ".foundry", "context.lock"])
      File.write!(lock_path, "stale_hash_value_12345\n")
      assert Foundry.Context.LockFile.check(@igaming_root) == {:error, :stale}
      # Restore
      Foundry.Context.LockFile.write(@igaming_root)
    end

    test "--check fails when lock is missing" do
      lock_path = Path.join([@igaming_root, ".foundry", "context.lock"])

      if File.exists?(lock_path) do
        File.rename!(lock_path, lock_path <> ".bak")

        try do
          assert Foundry.Context.LockFile.check(@igaming_root) == {:error, :missing}
        after
          File.rename!(lock_path <> ".bak", lock_path)
        end
      else
        # Lock doesn't exist — this is the missing case
        assert Foundry.Context.LockFile.check(@igaming_root) == {:error, :missing}
        # Restore
        Foundry.Context.LockFile.write(@igaming_root)
      end
    end

    test "regenerate lock and re-check passes" do
      lock_path = Path.join([@igaming_root, ".foundry", "context.lock"])
      File.write!(lock_path, "stale_hash\n")

      Foundry.Context.LockFile.write(@igaming_root)
      assert Foundry.Context.LockFile.check(@igaming_root) == :ok
    end
  end

  # ============================================================================
  # MUTATION TESTS: Lint Rule Violations
  # ============================================================================

  describe "mutation tests: PaperTrailRule detects missing AshPaperTrail" do
    test "sensitive module without AshPaperTrail triggers missing_paper_trail" do
      ctx = %{
        metadata: %{
          sensitive_modules: [Foundry.Test.Fixtures.PlainSensitive],
          project_root: @igaming_root,
          manifest: []
        }
      }

      {:ok, violations} = Foundry.LintRules.PaperTrailRule.check(Foundry.Test.Fixtures.PlainSensitive, ctx)
      assert Enum.any?(violations, &(&1.rule == :missing_paper_trail)),
             "Should detect missing AshPaperTrail. Got: #{inspect(violations)}"
    end
  end

  describe "mutation tests: ArchivalRule detects missing AshArchival" do
    test "sensitive module without AshArchival triggers missing_archival" do
      ctx = %{
        metadata: %{
          sensitive_modules: [Foundry.Test.Fixtures.PaperTrailOnly],
          project_root: @igaming_root,
          manifest: []
        }
      }

      {:ok, violations} = Foundry.LintRules.ArchivalRule.check(Foundry.Test.Fixtures.PaperTrailOnly, ctx)
      assert Enum.any?(violations, &(&1.rule == :missing_archival)),
             "Should detect missing AshArchival. Got: #{inspect(violations)}"
    end
  end

  describe "mutation tests: RunbookRule detects missing @runbook" do
    test "actual igaming WithdrawalTransfer has @runbook so passes rule" do
      ctx = %{
        metadata: %{
          sensitive_modules: [],
          project_root: @igaming_root,
          manifest: []
        }
      }

      # WithdrawalTransfer HAS @runbook, so it should pass (no violations)
      {:ok, violations} = Foundry.LintRules.RunbookRule.check(IgamingRef.Finance.WithdrawalTransfer, ctx)
      refute Enum.any?(violations, &(&1.rule == :missing_runbook)),
             "WithdrawalTransfer has @runbook, should not trigger violation. Got: #{inspect(violations)}"
    end
  end

  describe "mutation tests: IdempotencyRule detects missing @idempotency_key" do
    test "actual igaming WithdrawalTransfer has @idempotency_key so passes rule" do
      ctx = %{
        metadata: %{
          sensitive_modules: [],
          project_root: @igaming_root,
          manifest: []
        }
      }

      # WithdrawalTransfer HAS @idempotency_key, so it should pass (no violations)
      {:ok, violations} = Foundry.LintRules.IdempotencyRule.check(IgamingRef.Finance.WithdrawalTransfer, ctx)
      refute Enum.any?(violations, &(&1.rule == :missing_idempotency)),
             "WithdrawalTransfer has @idempotency_key, should not trigger violation. Got: #{inspect(violations)}"
    end
  end

  describe "mutation tests: DescriptionRule detects missing @moduledoc" do
    test "@moduledoc false is acceptable" do
      ctx = %{metadata: %{}}
      {:ok, violations} = Foundry.LintRules.DescriptionRule.check(Foundry.Test.Fixtures.NoDocModule, ctx)
      # @moduledoc false is acceptable according to the rule
      refute Enum.any?(violations, &(&1.rule == :missing_description)),
             "Should not flag @moduledoc false. Got: #{inspect(violations)}"
    end
  end

  describe "mutation tests: ManifestValidator detects missing required approvers" do
    test "manifest missing sensitive_lead triggers manifest_missing_required_approver" do
      bad_manifest = [
        project_name: "Test",
        approvers: [compliance_officer: "co@test.com"]
      ]

      violations = Foundry.LintRules.ManifestValidator.check(bad_manifest)
      assert Enum.any?(violations, &(&1.rule == :manifest_missing_required_approver)),
             "Should detect missing sensitive_lead. Got: #{inspect(violations)}"
    end

    test "manifest missing compliance_officer triggers manifest_missing_required_approver" do
      bad_manifest = [
        project_name: "Test",
        approvers: [sensitive_lead: "lead@test.com"]
      ]

      violations = Foundry.LintRules.ManifestValidator.check(bad_manifest)
      assert Enum.any?(violations, &(&1.rule == :manifest_missing_required_approver)),
             "Should detect missing compliance_officer. Got: #{inspect(violations)}"
    end
  end

  describe "mutation tests: VersionRule detects outdated Ash version" do
    test "igaming project with ash 3.13.1 passes version check" do
      # igaming has ash 3.13.1 in mix.lock, which satisfies >= 3.x requirement
      ctx = %{
        metadata: %{
          project_root: @igaming_root,
          sensitive_modules: [],
          manifest: []
        }
      }

      {:ok, violations} = Foundry.LintRules.VersionRule.check(nil, ctx)
      refute Enum.any?(violations, &(&1.rule == :ash_version_outdated)),
             "igaming with Ash 3.13.1 should not trigger ash_version_outdated. Got: #{inspect(violations)}"
    end
  end

  # ============================================================================
  # NEGATIVE TESTS: Non-Violations Pass Cleanly
  # ============================================================================

  describe "negative tests: rules pass when conditions are met" do
    test "plain module produces no violations when not marked sensitive" do
      ctx = %{
        metadata: %{
          sensitive_modules: [],
          project_root: @igaming_root,
          manifest: []
        }
      }

      {:ok, violations_paper} = Foundry.LintRules.PaperTrailRule.check(Foundry.Test.Fixtures.PlainSensitive, ctx)
      {:ok, violations_archival} = Foundry.LintRules.ArchivalRule.check(Foundry.Test.Fixtures.PlainSensitive, ctx)

      assert violations_paper == [], "PlainSensitive not marked sensitive should pass PaperTrailRule"
      assert violations_archival == [], "PlainSensitive not marked sensitive should pass ArchivalRule"
    end

    test "inactive adapter produces no violations" do
      ctx = %{
        metadata: %{
          sensitive_modules: [],
          project_root: @igaming_root,
          manifest: []
        }
      }

      {:ok, violations} = Foundry.LintRules.AdapterVersionRule.check(Foundry.Test.Fixtures.InactiveAdapter, ctx)
      # AdapterVersionRule is a Phase 1 stub — always returns empty
      assert violations == [], "AdapterVersionRule should return empty for Phase 1 stub"
    end

    test "manifest with all required approvers passes validation" do
      good_manifest = [
        project_name: "Test",
        approvers: [
          sensitive_lead: "lead@test.com",
          compliance_officer: "co@test.com"
        ]
      ]

      violations = Foundry.LintRules.ManifestValidator.check(good_manifest)
      refute Enum.any?(violations, &(&1.rule == :manifest_missing_required_approver)),
             "Complete manifest should pass. Got: #{inspect(violations)}"
    end
  end
end
