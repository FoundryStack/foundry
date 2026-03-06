defmodule IgamingRef.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      IgamingRef.Repo,
      {Oban, Application.fetch_env!(:igaming_ref, Oban)}
    ]

    opts = [strategy: :one_for_one, name: IgamingRef.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule IgamingRef.Repo do
  use AshPostgres.Repo, otp_app: :igaming_ref

  def installed_extensions do
    ["ash-functions", "uuid-ossp", "citext"]
  end
end

# ---------------------------------------------------------------------------
# Domains
# ---------------------------------------------------------------------------

defmodule IgamingRef.Finance do
  @moduledoc "Ledger, wallets, and financial transfers — the financial core of the reference project."

  use Ash.Domain, otp_app: :igaming_ref

  resources do
    resource IgamingRef.Finance.Wallet
    resource IgamingRef.Finance.LedgerEntry
    resource IgamingRef.Finance.WithdrawalRequest
  end
end

defmodule IgamingRef.Players do
  @moduledoc "Player accounts, KYC, and self-exclusion."

  use Ash.Domain, otp_app: :igaming_ref

  resources do
    resource IgamingRef.Players.Player
    resource IgamingRef.Players.SelfExclusionRecord
  end
end

defmodule IgamingRef.Promotions do
  @moduledoc "Bonus campaigns, grants, and wagering."

  use Ash.Domain, otp_app: :igaming_ref

  resources do
    resource IgamingRef.Promotions.BonusCampaign
    resource IgamingRef.Promotions.BonusGrant
  end
end

defmodule IgamingRef.Accounts do
  @moduledoc "Authentication subjects and tokens. Always treated as sensitive by Foundry."

  use Ash.Domain, otp_app: :igaming_ref

  resources do
    resource IgamingRef.Accounts.User
    resource IgamingRef.Accounts.Token
  end
end
