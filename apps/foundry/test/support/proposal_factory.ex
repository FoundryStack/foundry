defmodule Foundry.ProposalFactory do
  @moduledoc """
  Test helpers for building Proposal structs and manifest fixtures.

  Uses struct construction directly (not Ash.create!) to avoid AshPaperTrail
  notification overhead — Proposal uses Ash.DataLayer.Simple so the struct
  is the canonical in-memory representation.
  """

  alias Foundry.Proposals.Proposal

  @doc """
  Builds a %Proposal{} struct in DRAFT state.
  Accepts keyword overrides for any attribute.
  """
  def build_proposal(attrs \\ []) do
    defaults = [
      id: "prop_#{System.unique_integer([:positive])}",
      state: :draft,
      change_class: :structural,
      operation: "Op.AddAttribute",
      operation_params: nil,
      diff: "--- a/foo.ex\n+++ b/foo.ex\n@@ -1 +1 @@\n-old\n+new",
      requester: "requester@example.com",
      adr_link: nil,
      approval_slot_1: nil,
      approval_slot_2: nil,
      blob_hashes: %{},
      lint_result: nil,
      impact_analysis: nil,
      migration_diff: nil,
      submitted_at: nil,
      applied_at: nil,
      committed_at: nil,
      git_commit_sha: nil,
      rejection_reason: nil,
      stale_reason: nil,
      superseded_by: nil,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      archived_at: nil
    ]

    merged = Keyword.merge(defaults, attrs)
    struct!(Proposal, merged)
  end

  @doc """
  Returns a slot map matching the shape RecordApproval builds.
  """
  def approval_slot(approver, role \\ :developer) do
    %{approver: approver, approver_role: role, approved_at: DateTime.utc_now()}
  end

  @doc """
  Writes a minimal manifest.exs to a temp directory and sets
  `:foundry, :current_project_root` for the duration of a test.

  Pass `on_exit` from your setup block so cleanup runs after the test.

  Options (keyword list) become the manifest keyword list body.
  Returns the temp dir path.
  """
  def with_manifest(on_exit_fn, opts \\ []) do
    dir = System.tmp_dir!() |> Path.join("foundry_test_#{System.unique_integer([:positive])}")
    write_manifest_to(dir, opts)
    Application.put_env(:foundry, :current_project_root, dir)

    on_exit_fn.(fn ->
      Application.delete_env(:foundry, :current_project_root)
      File.rm_rf!(dir)
    end)

    dir
  end

  @doc "Write a manifest.exs into a pre-existing directory."
  def write_manifest_to(dir, opts \\ []) do
    foundry_dir = Path.join(dir, ".foundry")
    File.mkdir_p!(foundry_dir)

    defaults = [
      project_name: "test_project",
      approvers: [
        sensitive_lead: "sensitive@example.com",
        domain_lead: "domain@example.com",
        platform_lead: "platform@example.com",
        compliance_officer: "compliance@example.com",
        developer: "dev@example.com"
      ],
      sensitive_resources: [],
      compliance_requirements: [],
      auto_apply: false
    ]

    manifest = Keyword.merge(defaults, opts)
    manifest_content = inspect(manifest, limit: :infinity)
    File.write!(Path.join(foundry_dir, "manifest.exs"), manifest_content)
    dir
  end
end
