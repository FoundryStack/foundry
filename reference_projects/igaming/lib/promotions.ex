defmodule IgamingRef.Promotions do
  @moduledoc """
  Promotions domain: manages promotional campaigns and bonus grants.

  Resources:
    - BonusCampaign
    - BonusGrant
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain]

  resources do
    resource IgamingRef.Promotions.BonusCampaign
    resource IgamingRef.Promotions.BonusGrant
  end
end
