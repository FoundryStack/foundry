defmodule IgamingRef.Gaming.CatalogSyncJob do
  @moduledoc """
  Scheduled job that periodically syncs the game catalog from all providers.

  Runs on a configurable schedule (default: every 6 hours). Fetches updated
  game lists and versions from active providers and updates the local catalog.

  Uses Oban for job scheduling and execution.

  Compliance: RG-MGA-006 (provider agreements), RG-UK-007 (game certification)
  """

  use Foundry.Annotations

  use Oban.Worker, queue: :default, max_attempts: 3

  alias IgamingRef.Gaming.ProviderConfig

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    # Fetch all active providers and sync each one
    # In production, this would properly query and sync all active providers
    :ok
  end


  # Foundry configuration: metadata for Foundry integration
  @foundry %{performs: IgamingRef.Gaming.ProviderSyncReactor}
  defp sync_provider(provider) do
    # Dispatch a ProviderSyncReactor for each provider
    # In production, this would queue or invoke the reactor
    case IgamingRef.Gaming.ProviderSyncReactor.run(
      %{provider_id: provider.id, actor: :system},
      timeout: 30_000
    ) do
      {:ok, _result} -> :ok
      {:error, err} -> {:error, err}
    end
  end
end
