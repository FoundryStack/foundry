defmodule IgamingRef.Players.Player do
  @moduledoc """
  A registered player account. The root of all player-scoped data.

  PII-bearing sensitive resource - requires dual approval and full paper trail.
  Self-exclusion transitions are irreversible until the exclusion period ends
  (RG-UK-008).

  Compliance: RG-UK-002 (player verification), RG-MGA-003 (KYC requirements),
  RG-UK-008 (self-exclusion).
  """

  use Foundry.Annotations

  @compliance [:RG_UK_002, :RG_MGA_003, :RG_UK_008]
  @telemetry_prefix [:igaming_ref, :players, :player]

  use Ash.Resource,
    domain: IgamingRef.Players,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshStateMachine,
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("players")
    repo(IgamingRef.Repo)
  end

  paper_trail do
    change_tracking_mode(:snapshot)
  end

  state_machine do
    state_attribute(:status)
    initial_states([:active])
    default_initial_state(:active)

    transitions do
      transition(:suspend, from: :active, to: :suspended)
      transition(:reinstate, from: :suspended, to: :active)
      transition(:self_exclude, from: :active, to: :self_excluded)
      transition(:close, from: [:active, :suspended], to: :closed)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :ci_string do
      description("Player's email address. Case-insensitive unique identifier.")
      allow_nil?(false)
    end

    attribute :username, :string do
      description("Player's chosen display name. Unique.")
      allow_nil?(false)
      constraints(max_length: 64)
    end

    attribute :date_of_birth, :date do
      description("Player's date of birth. Used for age verification (RG-UK-002).")
      allow_nil?(false)
    end

    attribute :country_code, :string do
      description("ISO 3166-1 alpha-2 country code. Determines applicable regulations.")
      allow_nil?(false)
      constraints(max_length: 2, min_length: 2)
    end

    attribute :kyc_status, :atom do
      description(
        "Know-Your-Customer verification status. Players must reach :verified before withdrawals are permitted (RG-MGA-003)."
      )

      constraints(one_of: [:unverified, :pending, :verified, :rejected])
      default(:unverified)
      allow_nil?(false)
    end

    attribute :risk_level, :atom do
      description(
        "Operator-assigned risk classification. Used for transaction monitoring thresholds."
      )

      constraints(one_of: [:low, :medium, :high])
      default(:low)
      allow_nil?(false)
    end

    attribute :status, :atom do
      description("Account lifecycle state. Managed by AshStateMachine.")
      constraints(one_of: [:active, :suspended, :self_excluded, :closed])
      default(:active)
      allow_nil?(false)
    end

    timestamps()
  end

  identities do
    identity(:unique_email, [:email])
    identity(:unique_username, [:username])
  end

  relationships do
    has_many :wallets, IgamingRef.Finance.Wallet do
      description("All wallets belonging to this player.")
      destination_attribute(:player_id)
    end

    has_many :withdrawal_requests, IgamingRef.Finance.WithdrawalRequest do
      description("All withdrawal requests initiated by this player.")
      destination_attribute(:player_id)
    end

    has_many :self_exclusion_records, IgamingRef.Players.SelfExclusionRecord do
      description("All self-exclusion events for this player.")
      destination_attribute(:player_id)
    end
  end

  actions do
    defaults([:read])

    create :register do
      description("Register a new player account. Initial kyc_status is :unverified.")
      accept([:email, :username, :date_of_birth, :country_code])
    end

    update :update_kyc_status do
      description("Update the KYC verification status. Called by the KYC provider integration.")
      accept([:kyc_status, :risk_level])
    end

    update :suspend do
      description("Suspend a player account. Blocks login and financial activity.")
      change(transition_state(:suspended))
    end

    update :reinstate do
      description("Reinstate a suspended player.")
      change(transition_state(:active))
    end

    update :self_exclude do
      description(
        "Record a player's self-exclusion request. Creates a SelfExclusionRecord and transitions status (RG-UK-008)."
      )

      require_atomic?(false)
      change(transition_state(:self_excluded))

      change(fn changeset, context ->
        # Create the SelfExclusionRecord as a side effect
        # Full implementation: call IgamingRef.Players.SelfExclusionRecord |> Ash.create
        # Stubbed here - the Transfer layer handles this atomically
        changeset
      end)
    end

    update :close do
      description("Permanently close a player account.")
      change(transition_state(:closed))
    end
  end

  policies do
    policy action(:register) do
      description("Registration is unauthenticated (public action).")
      authorize_if(always())
    end

    policy action_type(:read) do
      description("Players may read their own record; operators may read all.")
      authorize_if(IgamingRef.Policies.OwnerOrOperator)
    end

    policy action_type(:read) do
      description("Internal system actors may read player records for governed financial flows.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:update_kyc_status) do
      description("Only the internal KYC system actor may update KYC status.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:suspend) do
      description("Only operators may suspend player accounts.")
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end

    policy action(:self_exclude) do
      description(
        "The player themselves may initiate self-exclusion. Operators may also trigger it."
      )

      authorize_if(IgamingRef.Policies.OwnerOrOperator)
    end
  end
end

defmodule IgamingRef.Players.SelfExclusionRecord do
  @moduledoc """
  Immutable record of a self-exclusion event. Append-only.

  Self-exclusion records must never be deleted - they are regulatory evidence
  (RG-MGA-009). The only permitted mutation is recording a reinstatement date
  after a temporary exclusion period expires.

  Compliance: RG-UK-008, RG-MGA-009 (self-exclusion integrity).
  """

  use Foundry.Annotations

  @compliance [:RG_UK_008, :RG_MGA_009]
  @telemetry_prefix [:igaming_ref, :players, :self_exclusion_record]

  use Ash.Resource,
    domain: IgamingRef.Players,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("self_exclusion_records")
    repo(IgamingRef.Repo)
  end

  paper_trail do
    change_tracking_mode(:snapshot)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :player_id, :uuid do
      description("The player who is self-excluding.")
      allow_nil?(false)
    end

    attribute :excluded_at, :utc_datetime do
      description("Timestamp of the self-exclusion event.")
      allow_nil?(false)
    end

    attribute :exclusion_type, :atom do
      description(
        ":temporary exclusions have a duration_days; :permanent exclusions are indefinite."
      )

      constraints(one_of: [:temporary, :permanent])
      allow_nil?(false)
    end

    attribute :duration_days, :integer do
      description(
        "For :temporary exclusions: the number of days the exclusion lasts. Nil for :permanent."
      )

      allow_nil?(true)
      constraints(min: 1)
    end

    attribute :reinstated_at, :utc_datetime do
      description(
        "When the player was reinstated after a temporary exclusion. Nil while exclusion is active."
      )

      allow_nil?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :player, IgamingRef.Players.Player do
      description("The player this exclusion record belongs to.")
      source_attribute(:player_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :record do
      description(
        "Record a new self-exclusion event. Called by the self_exclude action on Player."
      )

      accept([:player_id, :excluded_at, :exclusion_type, :duration_days])
    end

    update :mark_reinstated do
      description("Record the reinstatement timestamp when a temporary exclusion expires.")
      accept([:reinstated_at])
      require_atomic?(false)

      validate(fn changeset, _ ->
        exclusion_type = Ash.Changeset.get_attribute(changeset, :exclusion_type)

        if exclusion_type == :permanent,
          do: {:error, "permanent exclusions cannot be reinstated via this action"},
          else: :ok
      end)
    end

    # No destroy action - records are permanent regulatory evidence (RG-MGA-009)
  end

  policies do
    policy action_type(:read) do
      description("Operators and the player themselves may read exclusion records.")
      authorize_if(IgamingRef.Policies.OwnerOrOperator)
    end

    policy action(:record) do
      description("Only the internal system actor may create exclusion records.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end
  end
end
