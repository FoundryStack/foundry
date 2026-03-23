defmodule IgamingRef.Finance.Transfer do
  @moduledoc """
  Represents a financial transfer between accounts or wallets.

  Immutable record of a movement of funds. All transfers are recorded with
  direction (credit/debit), amount, and reference information.

  Compliance: RG-MGA-001 (wallet integrity), RG-UK-003 (balance accuracy)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_001, :RG_UK_003]
  @telemetry_prefix [:igaming_ref, :finance, :transfer]

  use Ash.Resource,
    domain: IgamingRef.Finance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("transfers")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :from_wallet_id, :uuid do
      description("Source wallet UUID. The wallet funds are debited from.")
      allow_nil?(true)
    end

    attribute :to_wallet_id, :uuid do
      description("Destination wallet UUID. The wallet funds are credited to.")
      allow_nil?(true)
    end

    attribute :amount, :money do
      description("Amount transferred. Must be positive.")
      allow_nil?(false)
    end

    attribute :status, :atom do
      description("Transfer lifecycle state: :pending, :completed, :failed, :cancelled")
      constraints(one_of: [:pending, :completed, :failed, :cancelled])
      default(:pending)
      allow_nil?(false)
    end

    attribute :reason, :string do
      description("Reason for the transfer (e.g. 'withdrawal', 'bonus', 'correction')")
      allow_nil?(false)
      constraints(max_length: 255)
    end

    timestamps()
  end

  actions do
    defaults([:read])

    create :record do
      description("Record a new transfer between wallets.")
      accept([:from_wallet_id, :to_wallet_id, :amount, :reason])
    end

    update :mark_completed do
      description("Mark a transfer as completed.")
      accept([])
    end

    update :mark_failed do
      description("Mark a transfer as failed.")
      accept([])
    end
  end

  policies do
    policy action_type(:read) do
      description("Operators and actors involved may read transfers.")
      authorize_if(always())
    end

    policy action(:record) do
      description("Internal system actor may record transfers.")
      authorize_if(always())
    end
  end
end
