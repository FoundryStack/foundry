defmodule Foundry.Proposals.Proposal do
  @moduledoc """
  A proposed change to a target project's codebase. The central resource for
  Foundry's governance model.

  ## Storage

  Proposals are stored as JSON files at `.foundry/proposals/prop_<id>.json`
  in the target project's repository. This Ash resource validates and provides
  typed access to proposal state — `Foundry.Proposals.ProposalStore` handles
  reading and writing the JSON files (ADR-015).

  The data layer is `Ash.DataLayer.Simple` — proposals are constructed in-memory
  from the parsed JSON file. They are not stored in a database.

  ## State Machine

  DRAFT → PENDING_REVIEW → APPROVED → APPLIED → COMMITTED
                         ↓
                       REJECTED
  Any state → STALE (when blob hashes no longer match — ADR-009)
  PENDING_REVIEW → SUPERSEDED (when a newer proposal covers the same change)

  ## Approval Mechanics

  `:sensitive` proposals require two distinct approvers (dual approval — ADR-014).
  `:compliance` proposals require the compliance_officer and an ADR link.
  `:behavioral` proposals require the domain_lead.
  `:structural` proposals require any developer; may auto-apply if manifest configured.

  ## Paper Trail and Archival

  Proposals are sensitive resources in Foundry's own manifest (they contain diffs
  of potentially sensitive target platform code). AshPaperTrail and AshArchival
  are both required (INV-011, INV-012).

  ## ADR

  ADR-014 — Proposal Lifecycle.
  ADR-009 — Concurrent Proposals (blob hash stale detection).
  ADR-015 — Storage Model.
  """

  use Ash.Resource,
    domain: Foundry.Proposals,
    data_layer: Ash.DataLayer.Simple,
    extensions: [
      AshStateMachine,
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  alias Foundry.Proposals.{ApprovalSlot, BlobHash, LintResult, ImpactAnalysis}

  # ---------------------------------------------------------------------------
  # Attributes
  # ---------------------------------------------------------------------------

  attributes do
    attribute :id, :string do
      description "Proposal identifier. Format: prop_<ulid>. Used as the JSON filename stem."
      allow_nil? false
      primary_key? true
      generated? true
    end

    attribute :state, :atom do
      description "Current lifecycle state. Managed by AshStateMachine — do not set directly."
      constraints one_of: [
        :draft,
        :pending_review,
        :approved,
        :applied,
        :committed,
        :rejected,
        :stale,
        :superseded
      ]
      default :draft
    end

    attribute :change_class, :atom do
      description "Classification of this proposal per ADR-005. Set by Foundry.Copilot.Classifier at proposal creation. Never set by the copilot engine directly — only via the classifier."
      constraints one_of: [:structural, :behavioral, :sensitive, :compliance]
      allow_nil? false
    end

    attribute :operation, :string do
      description "The Op.* module name that generated this proposal. E.g. 'Op.AddRule', 'Op.AddAttribute'."
      allow_nil? false
    end

    attribute :operation_params, :map do
      description "The parameters passed to the operation. Stored for re-execution on approval."
    end

    attribute :diff, :string do
      description "The unified diff output from Igniter dry_run. May be nil for proposals in DRAFT state before generation completes."
      allow_nil? true
    end

    attribute :migration_diff, :string do
      description "The unified diff of any ash_postgres migration generated alongside the code change. Nil when no migration is part of this proposal."
      allow_nil? true
    end

    attribute :blob_hashes, {:array, BlobHash} do
      description "Git blob hashes of all files affected by this proposal at creation time. Used for stale detection (ADR-009). A proposal is STALE when any hash no longer matches the current HEAD."
      default []
    end

    attribute :lint_result, LintResult do
      description "Structured lint output from the pre-approval lint run. Nil until the proposal reaches PENDING_REVIEW."
      allow_nil? true
    end

    attribute :impact_analysis, ImpactAnalysis do
      description "Deterministic impact analysis computed by Foundry.Copilot.ImpactAnalyzer. Nil until the proposal reaches PENDING_REVIEW."
      allow_nil? true
    end

    attribute :adr_link, :string do
      description "ADR identifier linked to this proposal. Required for :compliance proposals (validated before PENDING_REVIEW transition). Optional for other classes."
      allow_nil? true
    end

    attribute :requester, :string do
      description "Email address of the user who created this proposal."
      allow_nil? false
    end

    attribute :approval_slot_1, ApprovalSlot do
      description "First approval slot. For :sensitive proposals: must be filled by sensitive_lead. For :behavioral: domain_lead. For :structural: any developer."
      allow_nil? true
    end

    attribute :approval_slot_2, ApprovalSlot do
      description "Second approval slot. Only used for :sensitive proposals (dual approval). Must be a different person from approval_slot_1. May be filled by domain_lead, platform_lead, or compliance_officer per manifest."
      allow_nil? true
    end

    attribute :submitted_at, :utc_datetime do
      description "When the proposal transitioned from DRAFT to PENDING_REVIEW."
      allow_nil? true
    end

    attribute :applied_at, :utc_datetime do
      description "When Igniter applied the change to the filesystem."
      allow_nil? true
    end

    attribute :committed_at, :utc_datetime do
      description "When the resulting git commit was created."
      allow_nil? true
    end

    attribute :git_commit_sha, :string do
      description "The SHA of the git commit created on apply. Nil until COMMITTED state."
      allow_nil? true
    end

    attribute :rejection_reason, :string do
      description "Human-provided reason when a proposal is REJECTED. Required on the reject action."
      allow_nil? true
    end

    attribute :stale_reason, :string do
      description "Which file(s) changed to make this proposal STALE. Populated by the stale detection job."
      allow_nil? true
    end

    attribute :superseded_by, :string do
      description "The proposal_id of the proposal that superseded this one. Nil unless state is :superseded."
      allow_nil? true
    end

    timestamps()
  end

  # ---------------------------------------------------------------------------
  # State Machine
  # ---------------------------------------------------------------------------

  state_machine do
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :submit, from: :draft, to: :pending_review do
        description "Move proposal from private draft to visible review queue. Triggers lint + impact analysis. Requires diff to be present."
      end

      transition :approve, from: :pending_review, to: :approved do
        description "Record an approval. For :sensitive proposals, both slots must be filled before state advances to :approved. For other classes, a single approval suffices."
      end

      transition :apply, from: :approved, to: :applied do
        description "Execute the Igniter operation (dry_run: false). For :structural auto-apply, this transition is triggered immediately on the approve action. For all other classes, requires a deliberate separate action."
      end

      transition :commit, from: :applied, to: :committed do
        description "Git commit created. Final terminal state for successful proposals."
      end

      transition :reject, from: :pending_review, to: :rejected do
        description "Proposal declined by an approver. rejection_reason is required."
      end

      transition :mark_stale, from: [:draft, :pending_review, :approved, :applied], to: :stale do
        description "Blob hash check (ADR-009) detected that a file this proposal touches has changed since the proposal was created. Proposal cannot be applied until regenerated. The :applied case is exceptional — Igniter has already written files but the commit has not been created. Recovery requires manual `mix foundry.proposals.mark-applied` after resolving the conflict (ADR-014 §Compilation Failure Path)."
      end

      transition :supersede, from: :pending_review, to: :superseded do
        description "A newer proposal covers the same change. superseded_by must be set."
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  actions do
    defaults [:read]

    create :create_draft do
      description "Create a new proposal in DRAFT state. Called by Foundry.Copilot.Engine after generating a diff."
      accept [
        :change_class, :operation, :operation_params, :diff, :migration_diff,
        :blob_hashes, :requester, :adr_link
      ]
    end

    update :submit do
      description "Submit a DRAFT proposal for review. Validates diff is present, runs lint + impact analysis, checks :compliance ADR link requirement."
      change transition_state(:pending_review)
      change set_attribute(:submitted_at, &DateTime.utc_now/0)
      validate present(:diff), message: "cannot submit a proposal without a diff"
      validate Foundry.Proposals.Validations.ComplianceAdrLinkPresent
    end

    update :approve do
      description "Record an approval. The approver identity and role are validated against the manifest by AuthorizedApprover policy. For :sensitive proposals, state only advances to :approved when both slots are filled. A requester cannot approve their own proposal."
      # No accept list — slot assignment is entirely driven by the RecordApproval change,
      # which reads the actor from action context and sets the correct slot (1 or 2).
      # Accepting :approval_slot_1 / :approval_slot_2 directly would allow a single caller
      # to fill both slots in one request, bypassing the two-distinct-humans constraint
      # from ADR-014 §Dual Approval Mechanics.
      change Foundry.Proposals.Changes.RecordApproval
      change Foundry.Proposals.Changes.AdvanceOnDualApproval
    end

    update :apply do
      description "Execute the Igniter operation. Runs Foundry.Operations.run/2 with dry_run: false. Sets applied_at."
      change transition_state(:applied)
      change set_attribute(:applied_at, &DateTime.utc_now/0)
    end

    update :commit do
      description "Record the git commit SHA after Igniter apply succeeds. Advances to COMMITTED."
      accept [:git_commit_sha]
      change transition_state(:committed)
      change set_attribute(:committed_at, &DateTime.utc_now/0)
    end

    update :reject do
      description "Reject the proposal. rejection_reason is required."
      accept [:rejection_reason]
      change transition_state(:rejected)
      validate present(:rejection_reason), message: "rejection reason is required"
    end

    update :mark_stale do
      description "Mark the proposal as stale when blob hash check detects an underlying file has changed."
      accept [:stale_reason]
      change transition_state(:stale)
    end

    update :supersede do
      description "Mark this proposal as superseded by a newer one."
      accept [:superseded_by]
      change transition_state(:superseded)
      validate present(:superseded_by), message: "superseded_by proposal_id is required"
    end
  end

  # ---------------------------------------------------------------------------
  # Policies
  # ---------------------------------------------------------------------------

  policies do
    policy action(:read) do
      description "DRAFT proposals are only visible to the requester. PENDING_REVIEW and later are visible to all project users."
      authorize_if Foundry.Proposals.Policies.ProposalVisibility
    end

    policy action(:approve) do
      description "Approver must be a named approver in the manifest with the correct role for this proposal's change_class. A requester cannot approve their own proposal."
      authorize_if Foundry.Proposals.Policies.AuthorizedApprover
    end

    policy action(:apply) do
      description ":structural auto-apply is triggered by the approval action. All other classes require a separate deliberate Apply action by an authorized approver."
      authorize_if Foundry.Proposals.Policies.AuthorizedApply
    end
  end

  # ---------------------------------------------------------------------------
  # Calculations
  # ---------------------------------------------------------------------------

  calculations do
    calculate :is_stale, :boolean, expr(state == :stale) do
      description "Whether this proposal has been invalidated by an underlying file change."
    end

    calculate :awaiting_second_approval, :boolean,
      expr(change_class == :sensitive and not is_nil(approval_slot_1) and is_nil(approval_slot_2)) do
      description "Whether this :sensitive proposal has one approval and is waiting for the second."
    end

    calculate :fully_approved, :boolean,
      Foundry.Proposals.Calculations.FullyApproved do
      description "Whether all required approvals for this proposal's change_class have been recorded."
    end
  end
end

# ---------------------------------------------------------------------------
# Embedded resources
# ---------------------------------------------------------------------------

defmodule Foundry.Proposals.ApprovalSlot do
  @moduledoc """
  Records a single approval event for a proposal.
  Slots are immutable once filled — an approver cannot change their approval.
  Revocation requires rejecting the proposal and creating a new one.
  See: ADR-014 §Dual Approval Mechanics.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :approver, :string do
      description "Email address of the approver."
      allow_nil? false
    end

    attribute :approver_role, :atom do
      description "The manifest role under which this approval was granted."
      constraints one_of: [:sensitive_lead, :domain_lead, :platform_lead, :compliance_officer, :developer]
      allow_nil? false
    end

    attribute :approved_at, :utc_datetime do
      description "Timestamp of the approval action."
      allow_nil? false
    end
  end
end

defmodule Foundry.Proposals.BlobHash do
  @moduledoc """
  A git blob hash for a single file at the time a proposal was created.
  Used for stale detection per ADR-009.
  If the file's current blob hash at HEAD differs from this value, the proposal is STALE.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :file_path, :string do
      description "Relative path from project root. E.g. 'lib/my_app/finance/wallet.ex'."
      allow_nil? false
    end

    attribute :blob_hash, :string do
      description "Git blob hash (SHA-256 format: 'sha256:abc...'). Computed at proposal creation."
      allow_nil? false
    end
  end
end

defmodule Foundry.Proposals.LintResult do
  @moduledoc """
  Structured output from the pre-approval lint run.
  Populated when a proposal transitions from DRAFT to PENDING_REVIEW.
  A proposal with :error severity violations cannot advance past PENDING_REVIEW.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :passed, :boolean do
      description "True if no :error severity violations were found."
      allow_nil? false
    end

    attribute :violations, {:array, Foundry.Proposals.LintViolation} do
      description "All violations found. May include :warning and :info severity items even when passed is true."
      default []
    end

    attribute :ran_at, :utc_datetime do
      description "When the lint run completed."
      allow_nil? false
    end
  end
end

defmodule Foundry.Proposals.LintViolation do
  @moduledoc "A single lint violation from the pre-approval lint run."

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :rule_id, :atom do
      description "The lint rule identifier. E.g. :missing_description, :missing_paper_trail."
      allow_nil? false
    end

    attribute :severity, :atom do
      description "Severity level. :error blocks submission. :warning and :info are informational."
      constraints one_of: [:error, :warning, :info]
      allow_nil? false
    end

    attribute :message, :string do
      description "Human-readable description of the violation."
      allow_nil? false
    end

    attribute :file_path, :string do
      description "The file path where the violation was detected. May be nil for manifest-level violations."
      allow_nil? true
    end

    attribute :module, :string do
      description "The module name where the violation was detected."
      allow_nil? true
    end
  end
end

defmodule Foundry.Proposals.ImpactAnalysis do
  @moduledoc """
  Deterministic impact analysis computed by Foundry.Copilot.ImpactAnalyzer.
  Not LLM-generated — derived from static analysis of the diff and the project's
  context graph. See: ADR-012 §Impact Tab.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :affected_modules, {:array, :string} do
      description "All modules directly or transitively affected by this change."
      default []
    end

    attribute :affected_tests, {:array, :string} do
      description "Test modules that reference affected_modules and should be re-run."
      default []
    end

    attribute :migration_required, :boolean do
      description "Whether this proposal includes a database migration."
      default false
    end

    attribute :migration_is_reversible, :boolean do
      description "Whether the generated migration includes a down/rollback path."
      allow_nil? true
    end

    attribute :touches_sensitive_resources, :boolean do
      description "Whether any affected module is in manifest.sensitive_resources."
      default false
    end

    attribute :compliance_requirements_affected, {:array, :string} do
      description "RG-* requirement IDs whose implementing modules are in affected_modules."
      default []
    end

    attribute :computed_at, :utc_datetime do
      description "When this analysis was computed."
      allow_nil? false
    end
  end
end
