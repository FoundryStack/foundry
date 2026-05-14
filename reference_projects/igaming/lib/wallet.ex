defmodule IgamingRef.Finance.Wallet do
  @moduledoc """
  Holds a player's current balance across a single currency denomination.

  Sensitive resource - requires dual approval for all changes (INV-001).
  State machine enforces that frozen wallets block debits.
  Balance is stored as Ash.Type.Money; all monetary arithmetic uses the
  ex_money library with the IgamingRef.Cldr backend.

  Compliance: RG-MGA-001 (wallet integrity), RG-UK-003 (balance accuracy).
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_001, :RG_UK_003]
  @telemetry_prefix [:igaming_ref, :finance, :wallet]

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
    table("wallets")
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
      transition(:freeze, from: :active, to: :frozen)
      transition(:unfreeze, from: :frozen, to: :active)
      transition(:close, from: [:active, :frozen], to: :closed)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :player_id, :uuid do
      description(
        "The ID of the player who owns this wallet. References IgamingRef.Players.Player."
      )

      allow_nil?(false)
    end

    attribute :currency, :string do
      description("ISO 4217 currency code, e.g. 'GBP', 'EUR', 'USD'. Immutable after creation.")
      allow_nil?(false)
      constraints(max_length: 3, min_length: 3)
    end

    attribute :balance, :money do
      description(
        "Current balance. Must never go negative - enforced by the SufficientBalance rule on all debit Transfers (RG-MGA-001)."
      )

      allow_nil?(false)
      default(Money.new(0, :GBP))
    end

    attribute :status, :atom do
      description(
        "Lifecycle state of this wallet. Managed by AshStateMachine. :frozen wallets reject debit actions."
      )

      constraints(one_of: [:active, :frozen, :closed])
      default(:active)
      allow_nil?(false)
    end

    timestamps()
  end

  relationships do
    belongs_to :player, IgamingRef.Players.Player do
      description("The player who owns this wallet.")
      source_attribute(:player_id)
      allow_nil?(false)
    end

    has_many :ledger_entries, IgamingRef.Finance.LedgerEntry do
      description("All financial movements recorded against this wallet.")
      destination_attribute(:wallet_id)
    end

    has_many :withdrawal_requests, IgamingRef.Finance.WithdrawalRequest do
      description("All withdrawal requests initiated from this wallet.")
      destination_attribute(:wallet_id)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      description("Open a new wallet for a player in the given currency.")
      accept([:player_id, :currency])

      change(fn changeset, _ ->
        currency = Ash.Changeset.get_attribute(changeset, :currency) || "GBP"
        Ash.Changeset.change_attribute(changeset, :balance, Money.new(0, currency))
      end)
    end

    update :credit do
      description("Add funds to the wallet balance. Creates a corresponding LedgerEntry.")
      accept([:balance])
      require_atomic?(false)

      argument :amount, :money do
        description("The amount to credit. Must be positive and in the wallet's currency.")
        allow_nil?(false)
      end

      change(fn changeset, _ ->
        amount = Ash.Changeset.get_argument(changeset, :amount)
        current = Ash.Changeset.get_attribute(changeset, :balance)
        Ash.Changeset.change_attribute(changeset, :balance, Money.add!(current, amount))
      end)

      validate(fn changeset, _ ->
        amount = Ash.Changeset.get_argument(changeset, :amount)
        if Money.positive?(amount), do: :ok, else: {:error, "amount must be positive"}
      end)
    end

    update :debit do
      description(
        "Remove funds from the wallet balance. Rejected if balance would go negative (RG-MGA-001) or wallet is frozen."
      )

      accept([])
      require_atomic?(false)

      argument :amount, :money do
        description("The amount to debit. Must be positive and in the wallet's currency.")
        allow_nil?(false)
      end

      validate(fn changeset, _ ->
        case Ash.Changeset.get_attribute(changeset, :status) do
          :frozen -> {:error, "cannot debit a frozen wallet"}
          :closed -> {:error, "cannot debit a closed wallet"}
          _ -> :ok
        end
      end)

      validate(fn changeset, _ ->
        amount = Ash.Changeset.get_argument(changeset, :amount)
        balance = Ash.Changeset.get_attribute(changeset, :balance)

        if Money.compare!(balance, amount) != :lt,
          do: :ok,
          else: {:error, "insufficient balance (RG-MGA-001)"}
      end)

      change(fn changeset, _ ->
        amount = Ash.Changeset.get_argument(changeset, :amount)
        current = Ash.Changeset.get_attribute(changeset, :balance)
        Ash.Changeset.change_attribute(changeset, :balance, Money.sub!(current, amount))
      end)
    end

    update :freeze do
      description("Freeze the wallet. Debits are rejected while frozen.")
      change(transition_state(:frozen))
    end

    update :unfreeze do
      description("Unfreeze a previously frozen wallet.")
      change(transition_state(:active))
    end

    update :close do
      description("Permanently close the wallet. Irreversible. Requires zero balance.")
      require_atomic?(false)
      change(transition_state(:closed))

      validate(fn changeset, _ ->
        balance = Ash.Changeset.get_attribute(changeset, :balance)

        if Money.zero?(balance),
          do: :ok,
          else: {:error, "wallet must have zero balance before closing"}
      end)
    end
  end

  policies do
    policy action(:create) do
      description("Wallet provisioning is performed by internal system actors.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action_type(:read) do
      description("Players may read their own wallets. Operators may read any wallet.")
      authorize_if(IgamingRef.Policies.OwnerOrOperator)
    end

    policy action_type(:read) do
      description("Internal system actors may read wallets during governed transfer execution.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:debit) do
      description(
        "Debit requires the wallet to be active. Enforced in the action validate - policy layer ensures actor is authorised."
      )

      authorize_if(IgamingRef.Policies.AuthenticatedSubject)
    end

    policy action(:credit) do
      description("Wallet credits are performed by internal system actors in the reference project.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:close) do
      description("Only compliance officers and platform leads may close wallets.")
      authorize_if(IgamingRef.Policies.ComplianceOrPlatformLead)
    end
  end
end
