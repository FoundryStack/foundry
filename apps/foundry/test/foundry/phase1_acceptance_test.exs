defmodule Foundry.Phase1AcceptanceTest do
  use ExUnit.Case, async: false
  @moduletag :phase1

  @ref_root Path.expand("../../reference_projects/igaming", __DIR__)

  # Helpers
  # Note: These are placeholders used by Step 3+ tests (currently skipped).
  defp run_task(task, args \\ []) do
    # Runs a Mix task in the reference project's directory via System.cmd.
    # Returns {stdout, exit_code}. Uses System.cmd instead of Mix.Task.run/2
    # because Mix.Task.run/2 executes in the current Mix project's registry,
    # not in the specified directory's project.
    {output, exit_code} = System.cmd("mix", [task | args], cd: @ref_root)
    {output, exit_code}
  end

  defp decode_json!(output), do: Jason.decode!(output)

  describe "Foundry.FileSystem" do
    @tag :skip
    test "permitted path in lib/ returns {:ok, content}" do
      # Placeholder for full FileSystem test suite
      # Will use: run_task/2, decode_json!/1
      _task = run_task("test")
      _decoded = decode_json!("{}")
      assert true
    end
  end

  describe "mix foundry.project.context <Module>" do
    @tag :skip
    test "all schema fields present for WithdrawalTransfer" do
      # Placeholder for module context test
      assert true
    end
  end

  describe "mix foundry.project.context (bulk)" do
    @tag :skip
    test "top-level keys present" do
      # Placeholder for bulk context test
      assert true
    end
  end

  describe "mix foundry.project.context --check" do
    @tag :skip
    test "exits 0 when lock is current" do
      # Placeholder for --check test
      assert true
    end
  end

  describe "mix foundry.lint.all" do
    @tag :skip
    test "clean run exits 0" do
      # Placeholder for lint test
      assert true
    end
  end

  describe "mix foundry.project.status" do
    @tag :skip
    test "top-level keys present" do
      # Placeholder for status test
      assert true
    end
  end

  describe "integration: CI pipeline simulation" do
    @tag :skip
    test "full sequence passes" do
      # Placeholder for integration test
      assert true
    end
  end
end
