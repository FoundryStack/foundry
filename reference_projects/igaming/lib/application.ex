defmodule IgamingRef.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:igaming_ref, :foundry_tasks_only, false) do
        # Skip Repo/Oban when running Foundry tasks (mix foundry.*) without a DB
        []
      else
        [
          IgamingRef.Repo,
          {Oban, Application.fetch_env!(:igaming_ref, Oban)}
        ]
      end

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

# Note: Domain modules are defined in dedicated files:
# - lib/finance.ex
# - lib/players.ex
# - lib/promotions.ex
# - lib/accounts.ex
# - lib/ops.ex
# - lib/gaming.ex
