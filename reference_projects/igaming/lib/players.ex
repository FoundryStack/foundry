defmodule IgamingRef.Players do
  @moduledoc """
  Players domain: manages player accounts and related records.

  Resources:
    - Player
    - SelfExclusionRecord
    - KYCDocument
    - KYCUploadToken
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain, AshPaperTrail.Domain],
    validate_config_inclusion?: false

  resources do
    resource IgamingRef.Players.Player
    resource IgamingRef.Players.SelfExclusionRecord
    resource IgamingRef.Players.KYCDocument
    resource IgamingRef.Players.KYCUploadToken
  end
end
