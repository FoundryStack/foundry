defmodule IgamingRef.Promotions do
  @moduledoc """
  Promotions domain: manages promotional campaigns and bonus grants.

  Resources:
    - BonusCampaign
    - BonusGrant
    - BonusTrigger
    - BonusConditionGroup
    - BonusCondition
    - BonusExecution
    - BonusEvent
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain, AshPaperTrail.Domain]

  resources do
    resource(IgamingRef.Promotions.BonusCampaign)
    resource(IgamingRef.Promotions.BonusGrant)
    resource(IgamingRef.Promotions.BonusTrigger)
    resource(IgamingRef.Promotions.BonusConditionGroup)
    resource(IgamingRef.Promotions.BonusCondition)
    resource(IgamingRef.Promotions.BonusExecution)
    resource(IgamingRef.Promotions.BonusEvent)
  end
end
