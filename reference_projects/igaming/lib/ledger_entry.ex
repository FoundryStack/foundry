defmodule IgamingRef.Finance.LedgerEntry do
  @moduledoc """
  Immutable record of every financial movement against a wallet.

  Append-only by policy - no update or destroy actions exist.
  Every credit, debit, bonus, wager, win, and reversal is recorded here.
  The sum of all LedgerEntry amounts for a wallet must always equal
  Wallet.balance (RG-UK-003).

  Compliance: RG-MGA-001, RG-MGA-002 (ledger immutability), RG-UK-003.
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_001, :RG_MGA_002, :RG_UK_003]
  @telemetry_prefix [:igaming_ref, :finance, :ledger_entry]

  use Ash.Resource,
    domain: IgamingRef.Finance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("ledger_entries")
    repo(IgamingRef.Repo)
  end

  paper_trail do
    change_tracking_mode(:snapshot)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :wallet_id, :uuid do
      description("The wallet this entry belongs to.")
      allow_nil?(false)
    end

    attribute :amount, :money do
      description(
        "The monetary amount of this movement. Always positive - direction is conveyed by the :direction attribute."
      )

      allow_nil?(false)
    end

    attribute :direction, :atom do
      description("Whether funds moved into (:credit) or out of (:debit) the wallet.")
      constraints(one_of: [:credit, :debit])
      allow_nil?(false)
    end

    attribute :kind, :atom do
      description(
        "The business reason for this movement. Used for reporting and compliance categorisation."
      )

      constraints(one_of: [:deposit, :withdrawal, :bonus, :wager, :win, :reversal])
      allow_nil?(false)
    end

    attribute :idempotency_key, :string do
      description(
        "Unique key preventing duplicate ledger entries for the same financial event. Provided by the calling Transfer."
      )

      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :reference_id, :string do
      description(
        "External reference identifier - e.g. the WithdrawalRequest ID or provider transaction reference."
      )

      allow_nil?(true)
      constraints(max_length: 255)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :wallet, IgamingRef.Finance.Wallet do
      description("The wallet this ledger entry belongs to.")
      source_attribute(:wallet_id)
      allow_nil?(false)
    end
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key] do
      description(
        "Prevents duplicate ledger entries from retry storms. The idempotency key is the Transfer's idempotency key scoped to this movement."
      )
    end
  end

  actions do
    # :read only - no update, no destroy. Append-only enforced by action absence.
    defaults([:read])

    create :record do
      description(
        "Append a new ledger entry. Called exclusively by Transfer modules - never called directly by application code."
      )

      accept([:wallet_id, :amount, :direction, :kind, :idempotency_key, :reference_id])

      validate(fn changeset, _ ->
        amount = Ash.Changeset.get_attribute(changeset, :amount)

        if Money.positive?(amount),
          do: :ok,
          else: {:error, "ledger entry amount must be positive"}
      end)
    end
  end

  policies do
    policy action_type(:read) do
      description("Operators and the wallet owner may read ledger entries.")
      authorize_if(IgamingRef.Policies.OwnerOrOperator)
    end

    policy action_type(:read) do
      description("Internal system actors may read ledger entries for transfer reconciliation.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:record) do
      description("Only Transfer modules (internal system actor) may create ledger entries.")
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end
  end
end
