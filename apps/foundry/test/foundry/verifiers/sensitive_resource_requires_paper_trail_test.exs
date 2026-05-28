defmodule Foundry.Verifiers.SensitiveResourceRequiresPaperTrailTest do
  use ExUnit.Case, async: false

  alias Foundry.Verifiers.SensitiveResourceRequiresPaperTrail

  import Foundry.ProposalFactory

  # We test verify/1 by constructing a minimal dsl_state map.
  # Spark.Dsl.Verifier.get_persisted(dsl_state, :module) reads from
  # dsl_state[:persist][:module], which is a plain map for testing.

  defp dsl_state(module) do
    %{persist: %{module: module}}
  end

  # ---------------------------------------------------------------------------
  # Stub modules for testing
  # ---------------------------------------------------------------------------

  defmodule WithPaperTrail do
    # Simulates a module that uses AshPaperTrail.Resource by having it in Spark.extensions
    def __spark_dsl_config__, do: %{}
  end

  defmodule WithoutPaperTrail do
    def __spark_dsl_config__, do: %{}
  end

  describe "sensitive resource without paper trail" do
    setup do
      with_manifest(&on_exit/1,
        sensitive_resources: [WithoutPaperTrail]
      )

      :ok
    end

    test "returns error" do
      result = SensitiveResourceRequiresPaperTrail.verify(dsl_state(WithoutPaperTrail))
      assert {:error, error} = result
      assert error.message =~ "AshPaperTrail"
      assert error.message =~ "INV-011"
    end
  end

  describe "non-sensitive resource" do
    setup do
      with_manifest(&on_exit/1, sensitive_resources: [])
      :ok
    end

    test "returns :ok regardless of paper trail" do
      assert :ok = SensitiveResourceRequiresPaperTrail.verify(dsl_state(WithoutPaperTrail))
    end
  end

  describe "missing manifest" do
    setup do
      dir = System.tmp_dir!() |> Path.join("foundry_vtest_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      Application.put_env(:foundry, :current_project_root, dir)

      on_exit(fn ->
        Application.delete_env(:foundry, :current_project_root)
        File.rm_rf!(dir)
      end)

      :ok
    end

    test "returns :ok when manifest cannot be read" do
      assert :ok = SensitiveResourceRequiresPaperTrail.verify(dsl_state(WithoutPaperTrail))
    end
  end
end
