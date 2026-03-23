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
    extensions: [AshArchival.Domain]

  resources do
    resource IgamingRef.Players.Player
    resource IgamingRef.Players.Player.Version
    resource IgamingRef.Players.SelfExclusionRecord
    resource IgamingRef.Players.SelfExclusionRecord.Version
    resource IgamingRef.Players.KYCDocument
    resource IgamingRef.Players.KYCDocument.Version
    resource IgamingRef.Players.KYCUploadToken
  end
end
