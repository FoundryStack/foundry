defmodule IgamingRef.Promotions.BonusEvaluationReactor do
  @moduledoc """
  Evaluates inbound bonus events against manager-configured triggers, conditions,
  and executions.

  Campaign logic is data-driven (Ash resources) while execution handlers remain
  explicit and whitelisted in code.
  """

  use Foundry.Annotations

  @idempotency_key :event_id
  @runbook "docs/runbooks/bonus_evaluation_reactor.md"
  @compliance [:RG_MGA_005, :RG_UK_011]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_evaluation_reactor]

  use Reactor

  require Ash.Query

  alias IgamingRef.Players.Rules.PlayerNotSelfExcluded

  alias IgamingRef.Promotions.{
    BonusCampaign,
    BonusCondition,
    BonusConditionGroup,
    BonusEvent,
    BonusExecution,
    BonusGrant,
    BonusGrantTransfer,
    BonusTrigger
  }

  input(:event_id)
  input(:actor)

  step :load_event do
    description("Load inbound BonusEvent by ID.")
    argument(:event_id, input(:event_id))

    run(fn inputs, _ ->
      event_id = Map.fetch!(inputs, :event_id)
      Ash.get(BonusEvent, event_id, actor: %{role: :operator})
    end)
  end

  step :load_event_state do
    description("Attach replay metadata to the loaded event.")
    argument(:event, result(:load_event))

    run(fn %{event: event}, _ ->
      {:ok, %{event: event, should_process: is_nil(event.processed_at)}}
    end)
  end

  step :load_player do
    description("Load event player for condition evaluation.")
    argument(:event_state, result(:load_event_state))

    run(fn %{event_state: %{event: event, should_process: should_process}}, _ ->
      if should_process do
        Ash.get(IgamingRef.Players.Player, event.player_id, actor: %{is_system: true})
      else
        {:ok, nil}
      end
    end)
  end

  step :load_active_campaigns do
    description("Load active campaigns eligible for trigger matching.")
    argument(:event_state, result(:load_event_state))

    run(fn %{event_state: %{should_process: should_process}}, _ ->
      if should_process do
        now = DateTime.utc_now()

        BonusCampaign
        |> Ash.Query.filter(status == :active and starts_at <= ^now)
        |> Ash.read(actor: :system)
      else
        {:ok, []}
      end
    end)
  end

  step :find_matching_campaigns do
    description("Filter campaigns by trigger and condition evaluation.")
    argument(:event_state, result(:load_event_state))
    argument(:event, result(:load_event))
    argument(:player, result(:load_player))
    argument(:campaigns, result(:load_active_campaigns))

    run(fn %{
             event_state: %{should_process: should_process},
             event: event,
             player: player,
             campaigns: campaigns
           },
           _ ->
      if should_process do
        matches =
          campaigns
          |> Enum.filter(&campaign_matches_event?(&1, event, player))
          |> Enum.map(& &1.id)

        {:ok, matches}
      else
        {:ok, []}
      end
    end)
  end

  step :execute_campaigns do
    description("Run configured execution handlers for each matching campaign.")
    argument(:event_state, result(:load_event_state))
    argument(:campaign_ids, result(:find_matching_campaigns))
    argument(:event, result(:load_event))
    argument(:player, result(:load_player))

    run(fn %{
             event_state: %{should_process: should_process},
             campaign_ids: campaign_ids,
             event: event,
             player: player
           },
           _ ->
      if should_process do
        Enum.reduce_while(campaign_ids, {:ok, []}, fn campaign_id, {:ok, acc} ->
          case execute_campaign(campaign_id, player, event) do
            {:ok, result} -> {:cont, {:ok, [result | acc]}}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)
      else
        {:ok, []}
      end
    end)
  end

  step :mark_processed do
    description("Mark BonusEvent as processed once execution stage completes.")
    argument(:event_state, result(:load_event_state))
    argument(:event, result(:load_event))
    wait_for(:execute_campaigns)

    run(fn %{event_state: %{event: event, should_process: should_process}}, _ ->
      if should_process do
        event
        |> Ash.Changeset.for_update(:mark_processed, %{})
        |> Ash.update(actor: %{is_system: true})
      else
        {:ok, event}
      end
    end)
  end

  defp campaign_matches_event?(campaign, event, player) do
    with {:ok, triggers} <- load_triggers(campaign.id),
         true <- Enum.any?(triggers, &matching_trigger?(&1, event)),
         {:ok, groups} <- load_condition_groups(campaign.id),
         {:ok, conditions} <- load_conditions(groups),
         true <- conditions_pass?(campaign, player, event, groups, conditions) do
      true
    else
      _ -> false
    end
  end

  defp load_triggers(campaign_id) do
    BonusTrigger
    |> Ash.Query.filter(campaign_id: campaign_id, enabled: true)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read(actor: :system)
  end

  defp load_condition_groups(campaign_id) do
    BonusConditionGroup
    |> Ash.Query.filter(campaign_id: campaign_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read(actor: :system)
  end

  defp load_conditions(groups) do
    group_ids = Enum.map(groups, & &1.id)

    if group_ids == [] do
      {:ok, []}
    else
      BonusCondition
      |> Ash.Query.filter(group_id in ^group_ids)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read(actor: :system)
    end
  end

  defp matching_trigger?(trigger, event) do
    trigger.enabled and trigger.kind == event.kind
  end

  defp conditions_pass?(campaign, player, event, groups, conditions) do
    groups_by_parent = Enum.group_by(groups, & &1.parent_group_id)
    conditions_by_group = Enum.group_by(conditions, & &1.group_id)
    root_groups = Map.get(groups_by_parent, nil, [])

    cond do
      root_groups == [] and groups == [] ->
        true

      root_groups == [] ->
        false

      true ->
        Enum.all?(
          root_groups,
          &evaluate_group(
            &1,
            groups_by_parent,
            conditions_by_group,
            campaign,
            player,
            event,
            MapSet.new()
          )
        )
    end
  end

  defp evaluate_group(
         group,
         groups_by_parent,
         conditions_by_group,
         campaign,
         player,
         event,
         visited
       ) do
    if MapSet.member?(visited, group.id) do
      false
    else
      visited = MapSet.put(visited, group.id)

      direct_results =
        conditions_by_group
        |> Map.get(group.id, [])
        |> Enum.sort_by(& &1.position)
        |> Enum.map(&evaluate_condition(&1, campaign, player, event))

      child_results =
        groups_by_parent
        |> Map.get(group.id, [])
        |> Enum.sort_by(& &1.position)
        |> Enum.map(
          &evaluate_group(
            &1,
            groups_by_parent,
            conditions_by_group,
            campaign,
            player,
            event,
            visited
          )
        )

      combine_group_results(group.combinator, direct_results ++ child_results)
    end
  end

  defp combine_group_results(:any, results), do: Enum.any?(results, & &1)
  defp combine_group_results(:all, results), do: Enum.all?(results, & &1)

  defp evaluate_condition(condition, campaign, player, event) do
    result =
      case condition.kind do
        :campaign_active ->
          campaign.status == :active

        :campaign_not_expired ->
          DateTime.compare(campaign.expires_at, DateTime.utc_now()) == :gt

        :player_not_self_excluded ->
          PlayerNotSelfExcluded.evaluate(%{player: player}, nil) == :ok

        :player_country_in ->
          countries = fetch_list_param(condition.params, "countries")
          player.country_code in countries

        :min_deposit_amount ->
          min_deposit_satisfied?(condition.params, event)

        :no_active_bonus ->
          no_active_bonus?(player.id)

        _ ->
          false
      end

    if condition.negated, do: not result, else: result
  end

  defp min_deposit_satisfied?(params, event) do
    required_pence = fetch_int_param(params, "amount_pence", 0)
    currency = event.currency || "GBP"
    required = Money.new(required_pence, currency)

    case event.amount do
      nil -> false
      amount -> Money.compare!(amount, required) in [:eq, :gt]
    end
  end

  defp no_active_bonus?(player_id) do
    case BonusGrant
         |> Ash.Query.filter(player_id: player_id, status: :active)
         |> Ash.read(actor: %{is_system: true}) do
      {:ok, []} -> true
      {:ok, _active_grants} -> false
      _ -> false
    end
  end

  defp execute_campaign(campaign_id, player, event) do
    with {:ok, executions} <- load_executions(campaign_id) do
      run_executions(campaign_id, player, event, executions)
    end
  end

  defp load_executions(campaign_id) do
    BonusExecution
    |> Ash.Query.filter(campaign_id: campaign_id, enabled: true)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read(actor: :system)
  end

  defp run_executions(campaign_id, player, event, []),
    do: grant_bonus(campaign_id, player.id, event)

  defp run_executions(campaign_id, player, event, executions) do
    Enum.reduce_while(executions, {:ok, []}, fn execution, {:ok, acc} ->
      case execute_handler(execution, campaign_id, player, event) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp execute_handler(execution, campaign_id, player, event) do
    case execution.kind do
      :grant_deposit_match ->
        grant_bonus(campaign_id, player.id, event)

      :grant_fixed_amount ->
        grant_bonus(campaign_id, player.id, event)

      :set_wagering_requirement ->
        {:ok, %{kind: :set_wagering_requirement, params: execution.params}}

      _ ->
        {:error, {:unsupported_execution, execution.kind}}
    end
  end

  defp grant_bonus(campaign_id, player_id, _event) do
    Reactor.run(BonusGrantTransfer, %{
      player_id: player_id,
      campaign_id: campaign_id,
      actor: :system
    })
  end

  defp fetch_list_param(params, key) do
    atom_key =
      case key do
        "countries" -> :countries
        _ -> nil
      end

    (Map.get(params || %{}, key) || (atom_key && Map.get(params || %{}, atom_key)) || [])
    |> Enum.map(&to_string/1)
  rescue
    _ -> []
  end

  defp fetch_int_param(params, key, default) do
    atom_key =
      case key do
        "amount_pence" -> :amount_pence
        _ -> nil
      end

    value = Map.get(params || %{}, key) || (atom_key && Map.get(params || %{}, atom_key))

    case value do
      int when is_integer(int) -> int
      bin when is_binary(bin) -> String.to_integer(bin)
      _ -> default
    end
  rescue
    _ -> default
  end
end
