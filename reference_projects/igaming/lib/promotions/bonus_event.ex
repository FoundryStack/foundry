defmodule IgamingRef.Promotions.BonusEvent do
  @moduledoc """
  Runtime inbound event evaluated by the bonus engine.

  Stores normalized trigger inputs so processing is idempotent and auditable.
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005, :RG_UK_011]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_event]

  use Ash.Resource,
    domain: IgamingRef.Promotions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource, AshArchival.Resource]

  paper_trail do
    change_tracking_mode(:snapshot)
  end

  postgres do
    table("bonus_events")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :kind, :atom do
      description("Inbound event kind used to match campaign triggers.")
      allow_nil?(false)
      constraints(one_of: [:deposit_completed, :manual_grant])
    end

    attribute :player_id, :uuid do
      description("Player associated with the inbound event.")
      allow_nil?(false)
    end

    attribute :wallet_id, :uuid do
      description("Wallet associated with the inbound event.")
      allow_nil?(true)
    end

    attribute :amount, :money do
      description("Event amount, usually the deposit amount for trigger evaluation.")
      allow_nil?(true)
    end

    attribute :currency, :string do
      description("ISO 4217 currency code for the event amount.")
      allow_nil?(true)
      constraints(max_length: 3, min_length: 3)
    end

    attribute :idempotency_key, :string do
      description("Deduplicates repeated event ingestion attempts.")
      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :payload, :map do
      description("Raw event payload for diagnostics and replay.")
      allow_nil?(false)
      default(%{})
    end

    attribute :processed_at, :utc_datetime_usec do
      description("Set when BonusEvaluationReactor finishes processing the event.")
      allow_nil?(true)
    end

    timestamps()
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key] do
      description("Prevents duplicate ingestion for the same business event.")
    end
  end

  actions do
    defaults([:read])

    create :ingest do
      description("Persist an inbound event before evaluation.")
      accept([:kind, :player_id, :wallet_id, :amount, :currency, :idempotency_key, :payload])
    end

    update :mark_processed do
      description("Mark an event as processed after evaluation.")
      require_atomic?(false)
      accept([])

      change(fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :processed_at, DateTime.utc_now())
      end)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end

    policy action(:ingest) do
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:mark_processed) do
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end
  end
end
