defmodule IgamingRef.Finance.WithdrawalRequest do
  @moduledoc """
  A player's request to withdraw funds from their wallet.

  Passes through a state machine: pending → approved/rejected → processing → completed.
  Provider routing details are captured on the approved→processing transition.

  Compliance: RG-UK-014 (withdrawal processing), RG-MGA-007 (withdrawal limits).
  """

  use Foundry.Annotations

  @compliance [:RG_UK_014, :RG_MGA_007]
  @telemetry_prefix [:igaming_ref, :finance, :withdrawal_request]

  use Ash.Resource,
    domain: IgamingRef.Finance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshStateMachine,
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("withdrawal_requests")
    repo(IgamingRef.Repo)
  end

  paper_trail do
    change_tracking_mode(:snapshot)
  end

  state_machine do
    state_attribute(:status)
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition(:approve, from: :pending, to: :approved)
      transition(:reject, from: :pending, to: :rejected)
      transition(:cancel, from: [:pending, :approved], to: :cancelled)
      transition(:mark_processing, from: :approved, to: :processing)
      transition(:mark_completed, from: :processing, to: :completed)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :player_id, :uuid do
      description("The player who initiated this withdrawal.")
      allow_nil?(false)
    end

    attribute :wallet_id, :uuid do
      description("The wallet from which funds will be withdrawn.")
      allow_nil?(false)
    end

    attribute :amount, :money do
      description(
        "The requested withdrawal amount. Validated against the player's daily limit by WithdrawalLimitNotExceeded rule."
      )

      allow_nil?(false)
    end

    attribute :status, :atom do
      description("Current lifecycle state. Managed by AshStateMachine.")
      constraints(one_of: [:pending, :approved, :processing, :completed, :rejected, :cancelled])
      default(:pending)
      allow_nil?(false)
    end

    attribute :provider, :string do
      description("Payment provider identifier (e.g. 'stripe', 'paypal'). Set on approval.")
      allow_nil?(true)
      constraints(max_length: 64)
    end

    attribute :provider_reference, :string do
      description("Provider-assigned transaction ID. Set when processing begins.")
      allow_nil?(true)
      constraints(max_length: 255)
    end

    attribute :rejection_reason, :string do
      description(
        "Human-readable reason for rejection. Required when status transitions to :rejected."
      )

      allow_nil?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :player, IgamingRef.Players.Player do
      description("The player who made this withdrawal request.")
      source_attribute(:player_id)
      allow_nil?(false)
    end

    belongs_to :wallet, IgamingRef.Finance.Wallet do
      description("The wallet funds will be debited from.")
      source_attribute(:wallet_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :create do
      description("Submit a new withdrawal request. Initial state is :pending.")
      accept([:player_id, :wallet_id, :amount])
    end

    update :approve do
      description("Approve the withdrawal request and record the chosen payment provider.")
      accept([:provider])
      change(transition_state(:approved))
      validate(present(:provider), message: "provider is required for approval")
    end

    update :reject do
      description("Reject the withdrawal request. rejection_reason is required.")
      accept([:rejection_reason])
      change(transition_state(:rejected))
      validate(present(:rejection_reason), message: "rejection_reason is required")
    end

    update :cancel do
      description("Cancel a pending or approved withdrawal request.")
      change(transition_state(:cancelled))
    end

    update :mark_processing do
      description(
        "Mark the withdrawal as in-flight with the provider. Records the provider reference."
      )

      accept([:provider_reference])
      change(transition_state(:processing))
    end

    update :mark_completed do
      description("Mark the withdrawal as successfully completed.")
      change(transition_state(:completed))
    end
  end

  policies do
    policy action(:create) do
      description(
        "Any authenticated player may create a withdrawal request for their own wallet."
      )

      authorize_if(IgamingRef.Policies.AuthenticatedSubject)
    end

    policy action_type(:read) do
      description("Players may read their own requests; operators may read all.")
      authorize_if(IgamingRef.Policies.OwnerOrOperator)
    end

    policy action_type(:read) do
      description("Internal system actors may read withdrawal requests during transfer execution.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:approve) do
      description("Only operators may approve withdrawal requests.")
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end

    policy action(:reject) do
      description("Only operators may reject withdrawal requests.")
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end

    policy action(:mark_processing) do
      description("Internal system actors advance approved withdrawals to :processing.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:mark_completed) do
      description("Internal system actors complete withdrawals after provider confirmation.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end
  end
end
