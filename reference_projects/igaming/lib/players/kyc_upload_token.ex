defmodule IgamingRef.Players.KYCUploadToken do
  @moduledoc """
  Short-lived token that authorizes a player to upload KYC documents.

  Tokens are single-use and expire after a configurable duration (default 1 hour).
  Once a document is uploaded with a token, the token is marked as consumed.

  Compliance: RG-MGA-003 (KYC requirements), RG-UK-002 (player verification)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_003, :RG_UK_002]
  @telemetry_prefix [:igaming_ref, :players, :kyc_upload_token]

  use Ash.Resource,
    domain: IgamingRef.Players,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table("kyc_upload_tokens")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :player_id, :uuid do
      description("The player authorized to upload with this token.")
      allow_nil?(false)
    end

    attribute :token, :string do
      description("The opaque token string. Used as authorization header in upload requests.")
      allow_nil?(false)
      constraints(max_length: 256)
    end

    attribute :expires_at, :utc_datetime do
      description("Token expiration time. After this, uploads are rejected.")
      allow_nil?(false)
    end

    attribute :consumed_at, :utc_datetime do
      description("When the token was used to upload a document. Nil if not yet consumed.")
      allow_nil?(true)
    end

    attribute :consumed_by_document_id, :uuid do
      description("The KYCDocument that used this token. Nil if not yet consumed.")
      allow_nil?(true)
    end

    create_timestamp(:created_at)
  end

  relationships do
    belongs_to :player, IgamingRef.Players.Player do
      description("The player authorized to upload with this token.")
      source_attribute(:player_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :generate do
      description("Generate a new upload token for a player.")
      accept([:player_id])

      change(fn changeset, _ ->
        token = generate_token()
        expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)
        changeset
        |> Ash.Changeset.change_attribute(:token, token)
        |> Ash.Changeset.change_attribute(:expires_at, expires_at)
      end)
    end

    update :mark_consumed do
      description("Mark the token as consumed by a KYC document upload.")
      accept([:consumed_by_document_id])
      require_atomic?(false)

      change(fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :consumed_at, DateTime.utc_now())
      end)
    end
  end

  policies do
    policy action_type(:read) do
      description("Players may read their own tokens; operators may read all.")
      authorize_if(always())
    end

    policy action(:generate) do
      description("Authenticated players may request upload tokens.")
      authorize_if(always())
    end

    policy action(:mark_consumed) do
      description("System may mark tokens as consumed after successful upload.")
      authorize_if(always())
    end
  end

  # Private helpers
  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
