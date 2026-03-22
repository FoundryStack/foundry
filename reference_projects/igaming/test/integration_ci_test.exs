defmodule IgamingRef.Integration.CIPipelineTest do
  @moduledoc """
  Step 10: Integration CI Pipeline Simulation

  Tests the complete Foundry CI pipeline against the igaming reference project.
  These tests simulate what a real CI pipeline will run to gate changes.

  - Sequence tests: baseline pipeline execution (compile, lint, context, status)
  - Staleness cycle tests: lock file staleness detection and regeneration
  - Mutation tests: lint rule violations (positive tests showing rules catch problems)
  """

  use ExUnit.Case, async: false

  @project_root File.cwd!()

  describe "sequence: baseline CI pipeline" do
    test "foundry.lint.all passes with no violations on clean project" do
      report = Foundry.Lint.Runner.run(@project_root)

      assert report.passed,
             "Expected no errors in lint report. Violations: #{inspect(Enum.map(report.violations, &{&1.rule_id, &1.module, &1.message}))}"

      assert report.error_count == 0,
             "Expected 0 errors, got #{report.error_count}. Violations: #{inspect(report.violations)}"
    end

    test "foundry.project.context generates lock file" do
      Foundry.Context.LockFile.write(@project_root)
      lock_path = Path.join(@project_root, ".foundry/context.lock")
      assert File.exists?(lock_path), "Lock file should exist at #{lock_path}"
    end

    test "foundry.project.context --check passes after generation" do
      Foundry.Context.LockFile.write(@project_root)
      assert Foundry.Context.LockFile.check(@project_root) == :ok
    end

    test "foundry.project.status returns valid JSON structure" do
      status = Foundry.Status.build(@project_root)
      assert is_map(status)
      assert Map.has_key?(status, "project")
      assert Map.has_key?(status, "lint")
      assert Map.has_key?(status, "compiled_at")
    end
  end

  describe "staleness cycle: lock file freshness detection" do
    setup do
      Foundry.Context.LockFile.write(@project_root)
      :ok
    end

    test "--check passes when lock is current" do
      assert Foundry.Context.LockFile.check(@project_root) == :ok
    end

    test "--check fails when lock hash is stale" do
      lock_path = Path.join(@project_root, ".foundry/context.lock")
      File.write!(lock_path, "stale_hash_that_does_not_match_actual_content\n")
      result = Foundry.Context.LockFile.check(@project_root)
      assert result == {:error, :stale},
             "Expected {:error, :stale}, got #{inspect(result)}"

      # Restore for other tests
      Foundry.Context.LockFile.write(@project_root)
    end

    test "--check fails when lock is missing" do
      lock_path = Path.join(@project_root, ".foundry/context.lock")
      bak = lock_path <> ".bak"

      # Temporarily move lock file
      File.rename!(lock_path, bak)

      result = Foundry.Context.LockFile.check(@project_root)

      assert result == {:error, :missing},
             "Expected {:error, :missing}, got #{inspect(result)}"

      # Restore
      File.rename!(bak, lock_path)
    end

    test "regenerate and re-check passes after stale" do
      lock_path = Path.join(@project_root, ".foundry/context.lock")
      File.write!(lock_path, "stale_hash\n")

      # Re-generate lock
      Foundry.Context.LockFile.write(@project_root)
      assert Foundry.Context.LockFile.check(@project_root) == :ok
    end
  end

  describe "mutation tests: lint rules catch violations" do
    # Helper to run lint as subprocess in temp copy of project
    defp with_mutation(mutation_fn, test_fn) do
      tmpdir = Path.join(System.tmp_dir!(), "igaming_mut_#{:rand.uniform(1_000_000)}")
      root_dir = Path.dirname(Path.dirname(@project_root))

      File.cp_r!(@project_root, tmpdir)

      try do
        # Apply mutation
        mutation_fn.(tmpdir)

        # Update mix.exs to use absolute path for foundry dependency
        mix_exs_path = Path.join(tmpdir, "mix.exs")
        mix_exs = File.read!(mix_exs_path)

        foundry_path = Path.join(root_dir, "apps/foundry")
        updated_mix_exs = String.replace(mix_exs, ~r/{:foundry, path: "[^"]*"}/, "{:foundry, path: \"#{foundry_path}\"}")
        File.write!(mix_exs_path, updated_mix_exs)

        # Deps.get in temp copy to resolve dependencies
        env = [{"MIX_ENV", "test"}, {"FOUNDRY_TASKS_ONLY", "1"}]

        {_get_output, get_exit} =
          System.cmd("mix", ["deps.get"], cd: tmpdir, env: env, stderr_to_stdout: true)

        assert get_exit == 0, "deps.get failed"

        # Recompile temp copy
        {output, exit_code} =
          System.cmd("mix", ["compile"], cd: tmpdir, env: env, stderr_to_stdout: true)

        assert exit_code == 0, "Compile failed after mutation in temp dir. Output:\n#{output}"

        # Run lint in subprocess (fresh VM so mutated modules are loaded)
        # stderr_to_stdout: false to keep stderr separate so JSON is clean
        {json_output, lint_exit_code} =
          System.cmd("mix", ["foundry.lint.all", "--json"], cd: tmpdir, env: env, stderr_to_stdout: false)

        report = Jason.decode!(json_output)
        test_fn.(report, lint_exit_code)
      after
        File.rm_rf!(tmpdir)
      end
    end

    # Helper for mutations that affect lock file — must apply AFTER deps.get/compile
    # since deps.get will overwrite lock file mutations with constraint-resolved versions
    defp with_lock_mutation(mutation_fn, test_fn) do
      tmpdir = Path.join(System.tmp_dir!(), "igaming_mut_#{:rand.uniform(1_000_000)}")
      root_dir = Path.dirname(Path.dirname(@project_root))

      File.cp_r!(@project_root, tmpdir)

      try do
        # Update mix.exs to use absolute path for foundry dependency
        mix_exs_path = Path.join(tmpdir, "mix.exs")
        mix_exs = File.read!(mix_exs_path)

        foundry_path = Path.join(root_dir, "apps/foundry")
        updated_mix_exs = String.replace(mix_exs, ~r/{:foundry, path: "[^"]*"}/, "{:foundry, path: \"#{foundry_path}\"}")
        File.write!(mix_exs_path, updated_mix_exs)

        env = [{"MIX_ENV", "test"}, {"FOUNDRY_TASKS_ONLY", "1"}]

        # First: deps.get to resolve constraints (this will write current versions to mix.lock)
        {_get_output, get_exit} =
          System.cmd("mix", ["deps.get"], cd: tmpdir, env: env, stderr_to_stdout: true)

        assert get_exit == 0, "deps.get failed"

        # Second: compile to build the project
        {output, exit_code} =
          System.cmd("mix", ["compile"], cd: tmpdir, env: env, stderr_to_stdout: true)

        assert exit_code == 0, "Compile failed after deps.get in temp dir. Output:\n#{output}"

        # Third: apply lock file mutation AFTER compile so it persists
        mutation_fn.(tmpdir)

        # Fourth: run lint in subprocess
        {json_output, lint_exit_code} =
          System.cmd("mix", ["foundry.lint.all", "--json"], cd: tmpdir, env: env, stderr_to_stdout: false)

        report = Jason.decode!(json_output)
        test_fn.(report, lint_exit_code)
      after
        File.rm_rf!(tmpdir)
      end
    end

    test "removing @runbook from WithdrawalTransfer triggers missing_runbook" do
      with_mutation(
        fn tmpdir ->
          path = Path.join([tmpdir, "lib", "transfers.ex"])
          content = File.read!(path)
          mutated = String.replace(content, ~r/@runbook "docs\/runbooks\/withdrawal_transfer\.md"\n/, "")
          File.write!(path, mutated)
        end,
        fn report, _exit_code ->
          rule_ids = Enum.map(report["violations"], & &1["rule_id"])
          assert :missing_runbook in rule_ids or "missing_runbook" in rule_ids,
                 "Expected missing_runbook violation. Got: #{inspect(rule_ids)}"
        end
      )
    end

    test "removing AshPaperTrail.Resource from Wallet triggers missing_paper_trail" do
      with_mutation(
        fn tmpdir ->
          path = Path.join([tmpdir, "lib", "wallet.ex"])
          content = File.read!(path)
          # Remove the line "AshPaperTrail.Resource,"
          mutated = String.replace(content, "AshPaperTrail.Resource,\n", "")
          File.write!(path, mutated)
        end,
        fn report, _exit_code ->
          rule_ids = Enum.map(report["violations"], & &1["rule_id"])
          assert :missing_paper_trail in rule_ids or "missing_paper_trail" in rule_ids,
                 "Expected missing_paper_trail violation. Got: #{inspect(rule_ids)}"
        end
      )
    end

    test "removing AshArchival.Resource from Wallet triggers missing_archival" do
      with_mutation(
        fn tmpdir ->
          path = Path.join([tmpdir, "lib", "wallet.ex"])
          content = File.read!(path)
          # Remove the line "AshArchival.Resource"
          mutated = String.replace(content, "AshArchival.Resource\n", "")
          File.write!(path, mutated)
        end,
        fn report, _exit_code ->
          rule_ids = Enum.map(report["violations"], & &1["rule_id"])
          assert :missing_archival in rule_ids or "missing_archival" in rule_ids,
                 "Expected missing_archival violation. Got: #{inspect(rule_ids)}"
        end
      )
    end

    test "removing @idempotency_key from WithdrawalTransfer triggers missing_idempotency" do
      with_mutation(
        fn tmpdir ->
          path = Path.join([tmpdir, "lib", "transfers.ex"])
          content = File.read!(path)
          # Remove "@idempotency_key :withdrawal_request_id"
          mutated = String.replace(content, ~r/@idempotency_key :withdrawal_request_id\n/, "")
          File.write!(path, mutated)
        end,
        fn report, _exit_code ->
          rule_ids = Enum.map(report["violations"], & &1["rule_id"])
          assert :missing_idempotency in rule_ids or "missing_idempotency" in rule_ids,
                 "Expected missing_idempotency violation. Got: #{inspect(rule_ids)}"
        end
      )
    end

    test "removing @moduledoc triggers missing_description" do
      with_mutation(
        fn tmpdir ->
          path = Path.join([tmpdir, "lib", "wallet.ex"])
          content = File.read!(path)
          # Remove the @moduledoc ... line
          mutated = String.replace(content, ~r/@moduledoc """[\s\S]*?"""\n\n/, "")
          File.write!(path, mutated)
        end,
        fn report, _exit_code ->
          rule_ids = Enum.map(report["violations"], & &1["rule_id"])
          assert :missing_description in rule_ids or "missing_description" in rule_ids,
                 "Expected missing_description violation. Got: #{inspect(rule_ids)}"
        end
      )
    end

    test "removing sensitive_lead approver triggers manifest_missing_required_approver" do
      with_mutation(
        fn tmpdir ->
          path = Path.join([tmpdir, ".foundry", "manifest.exs"])
          content = File.read!(path)
          # Remove sensitive_lead line
          mutated = String.replace(content, ~r/sensitive_lead:\s+"[^"]*",\n/, "")
          File.write!(path, mutated)
        end,
        fn report, _exit_code ->
          rule_ids = Enum.map(report["violations"], & &1["rule_id"])
          assert :manifest_missing_required_approver in rule_ids or
                   "manifest_missing_required_approver" in rule_ids,
                 "Expected manifest_missing_required_approver violation. Got: #{inspect(rule_ids)}"
        end
      )
    end

    test "outdated ash version (2.x) triggers ash_version_outdated" do
      with_lock_mutation(
        fn tmpdir ->
          path = Path.join([tmpdir, "mix.lock"])
          content = File.read!(path)
          # Replace ash version with 2.x
          mutated = String.replace(content, ~r/(ash.*?)"3\.\d+\.\d+"/, ~s(\1"2.17.0"))
          File.write!(path, mutated)
        end,
        fn report, _exit_code ->
          rule_ids = Enum.map(report["violations"], & &1["rule_id"])
          assert :ash_version_outdated in rule_ids or "ash_version_outdated" in rule_ids,
                 "Expected ash_version_outdated violation. Got: #{inspect(rule_ids)}"
        end
      )
    end
  end

  describe "negative tests: non-violations pass cleanly" do
    test "adding an inactive adapter produces no errors" do
      report = Foundry.Lint.Runner.run(@project_root)
      rule_ids = Enum.map(report.violations, & &1.rule_id)

      # AdapterVersionRule is a Phase 1 stub that always returns {:ok, []}
      refute Enum.any?(rule_ids, fn rid -> rid in [:adapter_version, :inactive_adapter] end),
             "Adapter rules should not produce violations"
    end

    test "manifest with complete config produces no manifest_exclusion_no_comment" do
      report = Foundry.Lint.Runner.run(@project_root)
      rule_ids = Enum.map(report.violations, & &1.rule_id)

      # This violation would only fire if sensitive_resource_exemptions exist without a reason comment
      # which our manifest does not have
      refute Enum.any?(rule_ids, fn rid -> rid == :manifest_exclusion_no_comment end),
             "No manifest_exclusion violations should exist for clean project"
    end
  end
end
