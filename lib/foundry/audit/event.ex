defmodule Foundry.Audit.Event do
  @moduledoc """
  An append-only audit log entry. Records all approval events, apply events,
  and compliance-relevant state transitions for `:sensitive` and `:compliance`
  proposals.

  ## Storage

  Events are stored as JSONL records in `.foundry/audit.jsonl` in the target
  project's repository (ADR-015). Each state transition appends one line and
  commits the file. The git history of `audit.jsonl` is the authoritative
  inspection tool — `git log -p .foundry/audit.jsonl` shows every append with
  committer identity and timestamp.

  This Ash resource is the schema and validation layer. `Foundry.Audit.EventStore`
  handles reading and writing the JSONL file.

  ## Immutability

  No update or destroy actions exist. The append-only constraint is enforced by
  policy. Attempting to modify or delete an audit event is an error.

  ## Export

  `mix foundry.audit.export --from=<date> --to=<date>` reads the JSONL file,
  filters by timestamp, and outputs a formatted JSON array. For regulatory
  inspection, the git history is the primary evidence — the export is convenience.

  ## ADR

  ADR-014 §Audit Log.
  ADR-015 §Audit Log Format.
  """

  use Ash.Resource,
    domain: Foundry.Audit,
    data_layer: Ash.DataLayer.Simple
  # AshPaperTrail and AshArchival are intentionally absent here.
  #
  # AshPaperTrail would create an audit trail of changes to audit events —
  # i.e. the audit table auditing itself. Circular and meaningless.
  #
  # AshArchival (soft delete) is incompatible with an append-only resource:
  # there are no destroy actions for it to intercept, and soft-deleting an
  # audit record would itself require an audit event, creating infinite regress.
  #
  # Immutability is enforced by the absence of update and destroy actions.
  # That is a stronger guarantee than soft-delete: the record literally cannot
  # be modified through Ash, regardless of policy. The git history of
  # .foundry/audit.jsonl provides the tamper-evidence layer (ADR-015).

  # ---------------------------------------------------------------------------
  # Attributes
  # ---------------------------------------------------------------------------

  attributes do
    uuid_primary_key :id

    attribute :event_type, :atom do
      description "The type of audit event. See event type definitions below."
      constraints one_of: [
        :approved,        # An approval slot was filled
        :applied,         # Igniter apply executed
        :committed,       # Git commit created
        :rejected,        # Proposal rejected
        :superseded,      # Proposal superseded by a newer proposal
        :emergency_override  # Break-glass path used (approval_queue_blocked runbook)
      ]
      allow_nil? false
    end

    attribute :proposal_id, :string do
      description "The proposal_id this event relates to."
      allow_nil? false
    end

    attribute :change_class, :atom do
      description "The change class of the proposal at the time of this event."
      constraints one_of: [:structural, :behavioral, :sensitive, :compliance]
      allow_nil? false
    end

    attribute :actor, :string do
      description "Email address of the human who triggered this event. For :applied events triggered by auto-apply, this is the foundry-bot identity."
      allow_nil? false
    end

    attribute :actor_role, :atom do
      description "The manifest role under which the actor acted. nil for :applied and :committed events."
      constraints one_of: [:sensitive_lead, :domain_lead, :platform_lead, :compliance_officer, :developer, :foundry_bot]
      allow_nil? true
    end

    attribute :approval_slot, :integer do
      description "Which approval slot was filled (1 or 2). Only set for :approved events on :sensitive proposals."
      constraints one_of: [1, 2]
      allow_nil? true
    end

    attribute :diff_hash, :string do
      description "SHA-256 hash of the proposal's diff at the time of this event. Allows verification that the approved diff matches the applied diff."
      allow_nil? true
    end

    attribute :adr_link, :string do
      description "ADR identifier. Required for :compliance change events."
      allow_nil? true
    end

    attribute :commit_sha, :string do
      description "The git commit SHA. Only set for :applied and :committed events."
      allow_nil? true
    end

    attribute :notes, :string do
      description "Free-text notes. Required for :emergency_override events. Optional for others."
      allow_nil? true
    end

    attribute :occurred_at, :utc_datetime do
      description "When this event occurred. Set at creation time."
      allow_nil? false
    end

    timestamps()
  end

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  actions do
    defaults [:read]

    create :record do
      description "Append a new audit event. This is the only write action — there is no update or destroy."
      accept [
        :event_type, :proposal_id, :change_class, :actor, :actor_role,
        :approval_slot, :diff_hash, :adr_link, :commit_sha, :notes
      ]
      change set_attribute(:occurred_at, &DateTime.utc_now/0)
      validate Foundry.Audit.Validations.ComplianceAdrLinkPresent
      validate Foundry.Audit.Validations.EmergencyOverrideNotes
    end
  end

  # ---------------------------------------------------------------------------
  # Policies
  # ---------------------------------------------------------------------------

  policies do
    policy action(:read) do
      description "All authenticated Foundry users can read audit events."
      authorize_if always()
    end

    policy action(:record) do
      description "Only the Foundry backend (foundry_bot identity) can create audit events. No user-initiated audit event creation."
      authorize_if Foundry.Audit.Policies.FoundryBotOnly
    end

    # No update or destroy policies — these actions do not exist.
    # The absence of update/destroy actions is the enforcement mechanism (INV per audit integrity).
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validations do
    validate Foundry.Audit.Validations.ComplianceAdrLinkPresent do
      description ":compliance change events must have an adr_link."
      message "adr_link is required for :compliance change events"
      where [change_class: :compliance, event_type: [:approved, :applied]]
    end

    validate present(:notes) do
      description "Emergency override events must have notes explaining the override."
      message "notes are required for emergency_override events"
      where [event_type: :emergency_override]
    end
  end
end
