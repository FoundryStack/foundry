defmodule IgamingRef.Gaming.ProviderSyncReactor do
  @moduledoc """
  Synchronizes the game catalog from a provider.

  Fetches the latest game list from a provider's API and creates or updates
  local Game, GameVersion, and GameCatalog records. Fully idempotent.

  Steps:
    1. Load and validate provider config
    2. Fetch game list from provider API
    3. Sync each game and its versions
    4. Update the catalog visibility

  Compliance: RG-MGA-006 (provider agreements), RG-UK-007 (game certification)
  """

  use Foundry.Annotations

  @idempotency_key :provider_id
  @runbook "docs/runbooks/provider_sync.md"
  @compliance [:RG_MGA_006, :RG_UK_007]
  @telemetry_prefix [:igaming_ref, :gaming, :provider_sync]

  use Reactor

  alias IgamingRef.Gaming.{ProviderConfig, Game}
  alias IgamingRef.Gaming.Rules.ProviderActive

  input(:provider_id)
  input(:actor)

  step :load_provider do
    description("Load and validate the provider configuration.")

    run(fn %{provider_id: pid}, _ ->
      with {:ok, config} <- Ash.get(ProviderConfig, pid, actor: :system),
           :ok <- ProviderActive.evaluate(%{provider_config: config}, nil) do
        {:ok, config}
      else
        {:error, :provider_inactive, message} -> {:error, message}
        {:error, err} -> {:error, err}
      end
    end)
  end

  step :fetch_games do
    description("Fetch the game list from the provider API.")
    argument(:provider, result(:load_provider))

    run(fn %{provider: config}, _ ->
      # In production, this calls the actual provider API via Req.get(config.api_url)
      # For reference: returns list of {game_code, title, category, rtp, volatility}
      {:ok, []}
    end)
  end

  step :sync_games do
    description("Sync each game from the fetched list.")
    argument(:provider_id, input(:provider_id))
    argument(:games, result(:fetch_games))

    run(fn %{provider_id: pid, games: game_list}, _ ->
      results =
        Enum.map(game_list, fn game_data ->
          Game
          |> Ash.Changeset.for_create(:sync, Map.merge(game_data, %{provider_id: pid}))
          |> Ash.create(actor: %{is_system: true})
        end)

      case Enum.filter(results, &match?({:error, _}, &1)) do
        [] -> {:ok, Enum.map(results, fn {:ok, game} -> game end)}
        errors -> {:error, errors}
      end
    end)
  end

  step :update_catalog do
    description("Update GameCatalog entries for the synced games.")
    argument(:games, result(:sync_games))

    run(fn %{games: games}, _ ->
      Enum.each(games, fn game ->
        # Get the current active version
        # In production, would properly query GameVersion
        {:ok, :catalog_updated}
      end)

      {:ok, :catalog_updated}
    end)
  end
end
