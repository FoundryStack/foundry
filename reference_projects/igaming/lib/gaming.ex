defmodule IgamingRef.Gaming do
  @moduledoc """
  Gaming domain: manages game catalogs, providers, and game configurations.

  Resources:
    - ProviderConfig
    - Game
    - GameVersion
    - GameCatalog
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain, AshPaperTrail.Domain],
    validate_config_inclusion?: false

  resources do
    resource IgamingRef.Gaming.ProviderConfig
    resource IgamingRef.Gaming.Game
    resource IgamingRef.Gaming.GameVersion
    resource IgamingRef.Gaming.GameCatalog
    resource IgamingRef.Gaming.GameSession
  end
end
