defmodule IgamingRef.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: IgamingRef.PubSub},
        IgamingRef.Web.Endpoint
      ] ++ data_children()

    opts = [strategy: :one_for_one, name: IgamingRef.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp data_children do
    if Application.get_env(:igaming_ref, :foundry_tasks_only, false) do
      # Keep the preview UI bootable even when Foundry tasks run without a DB.
      []
    else
      [
        IgamingRef.Repo,
        {Oban, Application.fetch_env!(:igaming_ref, Oban)}
      ]
    end
  end
end

defmodule IgamingRef.Repo do
  use AshPostgres.Repo, otp_app: :igaming_ref

  def installed_extensions do
    ["ash-functions", "uuid-ossp", "citext"]
  end

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end

# Note: Domain modules are defined in dedicated files:
# - lib/finance.ex
# - lib/players.ex
# - lib/promotions.ex
# - lib/accounts.ex
# - lib/ops.ex
# - lib/gaming.ex
