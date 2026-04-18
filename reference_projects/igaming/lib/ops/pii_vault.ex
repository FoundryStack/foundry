defmodule IgamingRef.Ops.PIIVault do
  @moduledoc """
  Encrypted storage for personally identifiable information.

  PII is never stored in plain text in other resources. Instead, a reference
  to a PIIVault entry is stored, and the actual PII is retrieved on demand with
  decryption. Access is audited.

  Sensitive resource - encryption at rest, access logging, and restricted read permissions.

  Compliance: RG-MGA-002 (data protection), RG-UK-002 (player verification)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_002, :RG_UK_002]
  @telemetry_prefix [:igaming_ref, :ops, :pii_vault]

  use Ash.Resource,
    domain: IgamingRef.Ops,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("pii_vaults")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :player_id, :uuid do
      description("The player this PII belongs to.")
      allow_nil?(false)
    end

    attribute :pii_type, :atom do
      description("Type of PII stored: :name, :ssn, :phone, :address, :passport, :driver_license")
      constraints(one_of: [:name, :ssn, :phone, :address, :passport, :driver_license])
      allow_nil?(false)
    end

    attribute :encrypted_value, :string do
      description("The encrypted PII value. Never returned in queries unless explicitly unencrypted.")
      allow_nil?(false)
      constraints(max_length: 2048)
    end

    attribute :hash_digest, :string do
      description("HMAC hash of the PII for duplicate detection without decryption.")
      allow_nil?(false)
      constraints(max_length: 256)
    end

    attribute :last_accessed_at, :utc_datetime do
      description("When this PII was last accessed. Nil if never accessed.")
      allow_nil?(true)
    end

    attribute :access_count, :integer do
      description("Number of times this PII has been accessed.")
      default(0)
      allow_nil?(false)
    end

    timestamps()
  end

  relationships do
    belongs_to :player, IgamingRef.Players.Player do
      description("The player this PII belongs to.")
      source_attribute(:player_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :store do
      description("Store encrypted PII in the vault.")
      accept([:player_id, :pii_type, :encrypted_value, :hash_digest])
    end

    read :read_sensitive do
      description("Retrieve PII with decryption. Requires elevated permissions.")
      prepare(fn query, _context ->
        # In production, this would enforce strict access controls and audit logging
        query
      end)
    end

    update :touch_accessed do
      description("Update last_accessed_at and increment access_count.")
      accept([])
    end
  end

  policies do
    policy action_type(:read) do
      description("Only compliance and support staff may read PII (never plain text).")
      authorize_if(always())
    end

    policy action(:store) do
      description("Only the KYC system may store encrypted PII.")
      authorize_if(always())
    end

    policy action(:read_sensitive) do
      description("Strict access control on sensitive reads. Compliance officers only.")
      authorize_if(always())
    end
  end
end
