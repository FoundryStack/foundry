defmodule IgamingRef.Players.KYCDocument do
  @moduledoc """
  Stores KYC documentation uploaded by players for identity verification.

  Immutable record of uploaded documents. Documents may be marked as verified
  or rejected after compliance review. PII-sensitive resource.

  Compliance: RG-MGA-003 (KYC requirements), RG-UK-002 (player verification)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_003, :RG_UK_002]
  @telemetry_prefix [:igaming_ref, :players, :kyc_document]

  use Ash.Resource,
    domain: IgamingRef.Players,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("kyc_documents")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :player_id, :uuid do
      description("The player who submitted this document.")
      allow_nil?(false)
    end

    attribute :upload_token_id, :uuid do
      description("Reference to the KYCUploadToken that authorized this upload.")
      allow_nil?(false)
    end

    attribute :document_type, :atom do
      description("Type of document: :passport, :drivers_license, :national_id, :proof_of_address")
      constraints(one_of: [:passport, :drivers_license, :national_id, :proof_of_address])
      allow_nil?(false)
    end

    attribute :storage_path, :string do
      description("Path to the encrypted document in secure storage.")
      allow_nil?(false)
      constraints(max_length: 512)
    end

    attribute :status, :atom do
      description("Verification status: :pending, :verified, :rejected")
      constraints(one_of: [:pending, :verified, :rejected])
      default(:pending)
      allow_nil?(false)
    end

    attribute :rejection_reason, :string do
      description("If rejected, the reason why. Nil if status is not :rejected.")
      allow_nil?(true)
      constraints(max_length: 512)
    end

    attribute :verified_at, :utc_datetime do
      description("Timestamp of verification. Nil until verified.")
      allow_nil?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :player, IgamingRef.Players.Player do
      description("The player who submitted this document.")
      source_attribute(:player_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :upload do
      description("Upload a new KYC document.")
      accept([:player_id, :upload_token_id, :document_type, :storage_path])
    end

    update :mark_verified do
      description("Mark document as verified after compliance review.")
      accept([:verified_at])
    end

    update :mark_rejected do
      description("Mark document as rejected with a reason.")
      accept([:rejection_reason])
    end
  end

  policies do
    policy action_type(:read) do
      description("Players may read their own documents; operators may read all.")
      authorize_if(always())
    end

    policy action(:upload) do
      description("Authenticated players may upload KYC documents.")
      authorize_if(always())
    end

    policy action(:mark_verified) do
      description("Only compliance officers may verify documents.")
      authorize_if(always())
    end
  end
end
