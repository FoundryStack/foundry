defmodule IgamingRef.Accounts.User do
  @moduledoc """
  Authentication subject for the platform. Linked to a Player record
  post-registration.

  Always treated as sensitive by Foundry - auth resources are added to the
  sensitive resource set automatically by the classifier regardless of manifest
  configuration. AshPaperTrail and AshArchival are required (INV-011, INV-012).

  Strategies: password (hashed via bcrypt), magic_link.
  """

  use Ash.Resource,
    domain: IgamingRef.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshAuthentication,
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("users")
    repo(IgamingRef.Repo)
  end

  paper_trail do
    change_tracking_mode(:snapshot)
  end

  authentication do
    strategies do
      password :password do
        identity_field(:email)
        sign_in_tokens_enabled?(true)
        confirmation_required?(false)

        resettable do
          sender(IgamingRef.Accounts.Emails.PasswordResetEmail)
        end
      end

      magic_link do
        identity_field(:email)
        require_interaction?(true)
        sender(IgamingRef.Accounts.Emails.MagicLinkEmail)
      end
    end

    tokens do
      enabled?(true)
      token_resource(IgamingRef.Accounts.Token)
      signing_secret(IgamingRef.Secrets)
      require_token_presence_for_authentication?(true)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :ci_string do
      description("User email address. Case-insensitive. Used as the authentication identity.")
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :hashed_password, :string do
      description("Bcrypt-hashed password. Never returned in read actions.")
      allow_nil?(true)
      sensitive?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_email, [:email])
  end

  actions do
    defaults([:read])
  end

  policies do
    policy action_type(:read) do
      description("Users may read their own record only.")
      authorize_if(IgamingRef.Policies.SelfOnly)
    end
  end
end

defmodule IgamingRef.Accounts.Token do
  @moduledoc """
  Authentication tokens - session, magic link, and password reset tokens.

  Always treated as sensitive. Tokens have short TTLs and are pruned
  automatically by AshAuthentication's token pruning job.
  """

  use Ash.Resource,
    domain: IgamingRef.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshAuthentication.TokenResource,
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("tokens")
    repo(IgamingRef.Repo)
  end

  paper_trail do
    change_tracking_mode(:snapshot)
  end

  actions do
    defaults([:read, :destroy])
  end
end

# ---------------------------------------------------------------------------
# Supporting modules required by AshAuthentication
# ---------------------------------------------------------------------------

defmodule IgamingRef.Secrets do
  @moduledoc false
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], IgamingRef.Accounts.User, _resource, _opts) do
    case Application.fetch_env(:igaming_ref, :token_signing_secret) do
      {:ok, secret} -> {:ok, secret}
      :error -> {:error, "token_signing_secret not configured"}
    end
  end
end
