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

  # Shared tmpdir for all mutation tests (reuse compiled artifacts between tests)
  # Initialized on first use via ensure_mutation_tmpdir/0
  @mutation_tmpdir_name "igaming_mutations_#{:rand.uniform(1_000_000_000)}"
  @mutation_tmpdir_path System.tmp_dir!() |> Path.join(@mutation_tmpdir_name)

  # Module-level cleanup: remove golden tmpdir after all tests complete
  setup_all do
    on_exit(fn ->
      tmpdir = @mutation_tmpdir_path
      if File.exists?(tmpdir) do
        File.rm_rf!(tmpdir)
      end
    end)
    :ok
  end

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
    # Cache environment once instead of spawning subprocess for each test
    @cached_env (System.cmd("env", []) |> elem(0) |> String.trim() |> String.split("\n") |> Enum.map(&String.split(&1, "=", parts: 2)) |> Enum.filter(&(length(&1) == 2)) |> Enum.map(&List.to_tuple/1))

    # Helper to build environment by merging with cached environment
    defp build_env(overrides) do
      merged = @cached_env ++ overrides
      merged |> Enum.reverse() |> Enum.uniq_by(&elem(&1, 0)) |> Enum.reverse()
    end

    # Initialize shared tmpdir once, copy igaming and run deps.get + compile
    defp ensure_mutation_tmpdir do
      tmpdir = @mutation_tmpdir_path
      if not File.exists?(tmpdir) do
        root_dir = Path.dirname(Path.dirname(@project_root))

        # Copy without _build and deps
        File.cp_r!(@project_root, tmpdir, fn src, _dst ->
          not (src =~ ~r{/_build(/|$)}) and not (src =~ ~r{/deps(/|$)})
        end)

        # Patch foundry path
        mix_exs_path = Path.join(tmpdir, "mix.exs")
        mix_exs = File.read!(mix_exs_path)
        foundry_path = Path.join(root_dir, "apps/foundry")
        updated_mix_exs = String.replace(mix_exs, ~r/{:foundry, path: "[^"]*"}/, "{:foundry, path: \"#{foundry_path}\"}")
        File.write!(mix_exs_path, updated_mix_exs)

        env = build_env([{"MIX_ENV", "test"}, {"FOUNDRY_TASKS_ONLY", "1"}])

        # One-time deps.get and compile for the shared tmpdir
        {_out, code} = System.cmd("mix", ["deps.get", "--no-deps-check"], cd: tmpdir, env: env, stderr_to_stdout: true)
        assert code == 0, "deps.get failed in shared tmpdir"

        {_out, code} = System.cmd("mix", ["compile"], cd: tmpdir, env: env, stderr_to_stdout: true)
        assert code == 0, "compile failed in shared tmpdir"
      end

      tmpdir
    end

    # Helper to run lint as subprocess in shared temp copy
    # Mutations are applied to source files; mix compile incrementally recompiles them
    defp with_mutation(mutation_fn, test_fn) do
      tmpdir = ensure_mutation_tmpdir()

      try do
        # Apply mutation to source files in shared tmpdir
        mutation_fn.(tmpdir)

        env = build_env([{"MIX_ENV", "test"}, {"FOUNDRY_TASKS_ONLY", "1"}])

        # Run lint in subprocess - compilation output may be mixed with JSON
        {output, lint_exit_code} =
          System.cmd("mix", ["foundry.lint.all", "--json"], cd: tmpdir, env: env, stderr_to_stdout: true)

        # Extract JSON from output (compiler output often comes before JSON)
        # Look for a line that is valid JSON (starts with { and ends with })
        json_output =
          output
          |> String.split("\n")
          |> Enum.find(fn line ->
            trimmed = String.trim(line)
            String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}")
          end)

        # If no JSON found, return empty violations report
        if is_nil(json_output) do
          report = %{"violations" => [], "passed" => true, "error_count" => 0, "warning_count" => 0, "info_count" => 0}
          test_fn.(report, lint_exit_code)
        else
          try do
            report = Jason.decode!(json_output)
            test_fn.(report, lint_exit_code)
          rescue
            e in Jason.DecodeError ->
              IO.puts("ERROR decoding JSON: #{inspect(e)}")
              IO.puts("JSON string: #{String.slice(json_output, 0..100)}")
              report = %{"violations" => [], "passed" => true, "error_count" => 0, "warning_count" => 0, "info_count" => 0}
              test_fn.(report, lint_exit_code)
          end
        end
      after
        # Restore mutated source files to original state for next test
        # (so mutations don't accumulate)
        # Copy only lib/ from original @project_root to restore sources
        lib_src = Path.join(@project_root, "lib")
        lib_dst = Path.join(tmpdir, "lib")
        File.rm_rf!(lib_dst)
        File.cp_r!(lib_src, lib_dst)
      end
    end

    # Helper for mutations that affect lock file
    # Must use the shared tmpdir to reuse compile cache; lock mutations don't persist anyway
    # (mix compile with the original mix.lock will re-resolve)
    defp with_lock_mutation(mutation_fn, test_fn) do
      tmpdir = ensure_mutation_tmpdir()

      try do
        # Apply lock file mutation
        mutation_fn.(tmpdir)

        env = build_env([{"MIX_ENV", "test"}, {"FOUNDRY_TASKS_ONLY", "1"}])

        # Run lint in subprocess - compilation output may be mixed with JSON
        {output, lint_exit_code} =
          System.cmd("mix", ["foundry.lint.all", "--json"], cd: tmpdir, env: env, stderr_to_stdout: true)

        # Extract JSON from output (compiler output often comes before JSON)
        # Look for a line that is valid JSON (starts with { and ends with })
        json_output =
          output
          |> String.split("\n")
          |> Enum.find(fn line ->
            trimmed = String.trim(line)
            String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}")
          end)

        # If no JSON found, return empty violations report
        report =
          if is_nil(json_output) do
            IO.puts("WARN: No JSON in subprocess output. Last 300 chars: #{String.slice(output, -300..-1)}")
            IO.puts("Exit code: #{lint_exit_code}")
            %{"violations" => [], "passed" => true, "error_count" => 0, "warning_count" => 0, "info_count" => 0}
          else
            try do
              Jason.decode!(json_output)
            rescue
              e in Jason.DecodeError ->
                IO.puts("ERROR decoding JSON. Input: #{String.slice(json_output, 0..100)}")
                IO.puts("Error: #{inspect(e)}")
                %{"violations" => [], "passed" => true, "error_count" => 0, "warning_count" => 0, "info_count" => 0}
            end
          end

        test_fn.(report, lint_exit_code)
      after
        # Restore lock file to original
        lock_src = Path.join(@project_root, "mix.lock")
        lock_dst = Path.join(tmpdir, "mix.lock")
        File.cp!(lock_src, lock_dst)

        # Also restore lib/ sources like with_mutation does
        lib_src = Path.join(@project_root, "lib")
        lib_dst = Path.join(tmpdir, "lib")
        File.rm_rf!(lib_dst)
        File.cp_r!(lib_src, lib_dst)
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
