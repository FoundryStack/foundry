defmodule IgamingRef.Policies.AuthenticatedSubject do
  @moduledoc """
  Allows any authenticated user (has an actor).

  Applied by: IgamingRef.Finance.Wallet,
              IgamingRef.Promotions.BonusCampaign,
              IgamingRef.Finance.WithdrawalRequest,
              IgamingRef.Players.Player
  """
  use Ash.Policy.SimpleCheck

  def match?(actor, _, _), do: actor != nil
  def describe(_), do: "is authenticated"
end

defmodule IgamingRef.Policies.OperatorOnly do
  @moduledoc """
  Allows only operator roles.

  Applied by: IgamingRef.Gaming.ProviderConfig,
              IgamingRef.Finance.WithdrawalRequest,
              IgamingRef.Promotions.BonusCampaign
  """
  use Ash.Policy.SimpleCheck

  def match?(actor, _, _) do
    case actor do
      %{role: :operator} -> true
      _ -> false
    end
  end

  def describe(_), do: "is operator"
end

defmodule IgamingRef.Policies.OwnerOrOperator do
  @moduledoc """
  Allows owner of the resource or any operator.

  Applied by: IgamingRef.Finance.Wallet,
              IgamingRef.Finance.LedgerEntry,
              IgamingRef.Finance.WithdrawalRequest,
              IgamingRef.Players.Player
  """
  use Ash.Policy.SimpleCheck

  def match?(%{role: :operator}, _, _), do: true
  def match?(%{is_system: true}, _, _), do: true

  def match?(actor, %{subject: %Ash.Changeset{data: data}}, _) do
    case {data, actor} do
      {%{owner_id: owner_id}, %{id: actor_id}} -> owner_id == actor_id
      _ -> false
    end
  end

  def match?(_, _, _), do: false
  def describe(_), do: "is owner or operator"
end

defmodule IgamingRef.Policies.SelfOnly do
  @moduledoc "Allows only reading/modifying one's own record"
  use Ash.Policy.SimpleCheck

  def match?(actor, %{subject: %Ash.Changeset{data: data}}, _) do
    case {data, actor} do
      {%{id: data_id}, %{id: actor_id}} -> data_id == actor_id
      _ -> false
    end
  end

  def match?(_, _, _), do: false
  def describe(_), do: "is viewing/editing own record"
end

defmodule IgamingRef.Policies.InternalSystemActor do
  @moduledoc """
  Allows internal system actors (jobs, async processes).

  Applied by: IgamingRef.Finance.LedgerEntry,
              IgamingRef.Promotions.BonusGrant,
              IgamingRef.Players.SelfExclusionRecord
  """
  use Ash.Policy.SimpleCheck

  def match?(actor, _, _) do
    case actor do
      %{is_system: true} -> true
      _ -> false
    end
  end

  def describe(_), do: "is internal system"
end

defmodule IgamingRef.Policies.ComplianceOrPlatformLead do
  @moduledoc """
  Allows compliance officers or platform leads.

  Applied by: IgamingRef.Finance.Wallet
  """
  use Ash.Policy.SimpleCheck

  def match?(actor, _, _) do
    case actor do
      %{role: role} when role in [:compliance, :platform_lead] -> true
      _ -> false
    end
  end

  def describe(_), do: "is compliance or platform lead"
end
