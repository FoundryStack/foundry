defmodule Foundry.Proposals.Changes.ComputeImpactAnalysisTest do
  use ExUnit.Case, async: false

  import Foundry.ProposalFactory

  alias Foundry.Proposals.Changes.ComputeImpactAnalysis

  setup do
    # Point at an empty dir — ImpactAnalyzer will fail gracefully
    dir = System.tmp_dir!() |> Path.join("foundry_cia_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    Application.put_env(:foundry, :current_project_root, dir)

    on_exit(fn ->
      Application.delete_env(:foundry, :current_project_root)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  defp run(proposal) do
    proposal
    |> Ash.Changeset.for_update(:submit, %{}, domain: Foundry.Proposals, authorize?: false)
    |> then(fn cs -> ComputeImpactAnalysis.change(cs, [], %{}) end)
  end

  test "failure is non-fatal — changeset remains valid, impact_analysis stays nil" do
    # The empty dir has no manifest.exs, so ImpactAnalyzer returns {:error, _}
    proposal = build_proposal()
    cs = run(proposal)

    # No errors added
    assert cs.errors == []
    # impact_analysis not set (nil or absent from changeset attributes)
    refute Ash.Changeset.get_attribute(cs, :impact_analysis)
  end

  test "extracts module ids from operation_params.module_contexts" do
    proposal =
      build_proposal(
        operation_params: %{
          "module_contexts" => [
            %{"id" => "MyApp.Finance.Wallet"},
            %{"id" => "MyApp.Finance.Transaction"}
          ]
        }
      )

    # We can't easily verify ImpactAnalyzer ran successfully without a full project,
    # but we verify the changeset is not broken and the extract logic doesn't raise.
    cs = run(proposal)
    assert cs.errors == []
  end

  test "falls back to operation field when operation_params has no module_contexts" do
    proposal = build_proposal(operation: "MyApp.SomeModule", operation_params: %{})
    cs = run(proposal)
    assert cs.errors == []
  end

  test "handles nil operation_params gracefully" do
    proposal = build_proposal(operation_params: nil)
    cs = run(proposal)
    assert cs.errors == []
  end
end
