defmodule Foundry.Verifiers.ComplianceResourceRequiresArchivalTest do
  use ExUnit.Case, async: false

  alias Foundry.Verifiers.ComplianceResourceRequiresArchival

  import Foundry.ProposalFactory

  defp dsl_state(module) do
    %{persist: %{module: module}}
  end

  defmodule ComplianceModule do
    def __spark_dsl_config__, do: %{}
  end

  defmodule NonComplianceModule do
    def __spark_dsl_config__, do: %{}
  end

  describe "compliance resource without AshArchival" do
    setup do
      with_manifest(&on_exit/1,
        compliance_requirements: [
          [implementing_modules: [ComplianceModule]]
        ]
      )

      :ok
    end

    test "returns error" do
      result = ComplianceResourceRequiresArchival.verify(dsl_state(ComplianceModule))
      assert {:error, error} = result
      assert error.message =~ "AshArchival"
      assert error.message =~ "INV-012"
    end
  end

  describe "non-compliance resource" do
    setup do
      with_manifest(&on_exit/1,
        compliance_requirements: [
          [implementing_modules: [ComplianceModule]]
        ]
      )

      :ok
    end

    test "returns :ok" do
      assert :ok = ComplianceResourceRequiresArchival.verify(dsl_state(NonComplianceModule))
    end
  end

  describe "no compliance requirements in manifest" do
    setup do
      with_manifest(&on_exit/1, compliance_requirements: [])
      :ok
    end

    test "returns :ok for any module" do
      assert :ok = ComplianceResourceRequiresArchival.verify(dsl_state(ComplianceModule))
    end
  end

  describe "missing manifest" do
    setup do
      dir = System.tmp_dir!() |> Path.join("foundry_cra_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      Application.put_env(:foundry, :current_project_root, dir)

      on_exit(fn ->
        Application.delete_env(:foundry, :current_project_root)
        File.rm_rf!(dir)
      end)

      :ok
    end

    test "returns :ok when manifest cannot be read" do
      assert :ok = ComplianceResourceRequiresArchival.verify(dsl_state(ComplianceModule))
    end
  end
end
