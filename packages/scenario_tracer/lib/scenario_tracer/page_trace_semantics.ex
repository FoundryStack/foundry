defmodule ScenarioTracer.PageTraceSemantics do
  @moduledoc false

  alias ExTracer.ActionSemantics

  @page_types ["page", :page, "live_page", :live_page]

  def page_flow?([%{flow: [first | _]} | _], lookup), do: page_node?(first.node_id, lookup)
  def page_flow?(_test_flows, _lookup), do: false

  def page_node?(node_id, lookup) when is_binary(node_id) do
    case Map.get(lookup.by_id, node_id) do
      %{type: type} when type in @page_types -> true
      _ -> false
    end
  end

  def page_node?(_, _lookup), do: false

  def wrap_flow(flow, lookup) do
    Enum.map(flow, fn step -> %{step: step, role: classify_role(step, lookup)} end)
  end

  def collapse_duplicate_mount_cycles(wrapped_flow) do
    do_collapse_duplicate_mount_cycles(wrapped_flow)
  end

  def meaningful_wrappers(wrapped_flow) do
    Enum.reject(wrapped_flow, &(&1.role == :test_observation))
  end

  def exact_action_candidate?(%{step: step, role: role}) do
    role == :app_behavior or is_binary(step.action) or
      String.contains?(step.focus_node_id || "", ":action:")
  end

  def semantic_key(%{step: step, role: role}) do
    {
      Map.get(step, :type),
      Map.get(step, :kind),
      ActionSemantics.normalize_action_name(Map.get(step, :action)),
      Map.get(step, :focus_node_id) || Map.get(step, :node_id),
      Map.get(step, :node_id),
      role
    }
  end

  def strip_wrappers(wrapped_flow), do: Enum.map(wrapped_flow, & &1.step)

  defp do_collapse_duplicate_mount_cycles(wrapped_flow) do
    max_cycle = div(length(wrapped_flow), 2)

    candidate_range =
      if max_cycle < 1 do
        []
      else
        1..max_cycle
      end

    case Enum.find(candidate_range, &duplicated_mount_cycle?(wrapped_flow, &1)) do
      nil ->
        wrapped_flow

      cycle_size ->
        wrapped_flow
        |> Enum.take(cycle_size)
        |> Kernel.++(Enum.drop(wrapped_flow, cycle_size * 2))
        |> do_collapse_duplicate_mount_cycles()
    end
  end

  defp duplicated_mount_cycle?(_wrapped_flow, cycle_size) when cycle_size < 1, do: false

  defp duplicated_mount_cycle?(wrapped_flow, cycle_size) do
    leading = Enum.take(wrapped_flow, cycle_size)
    repeated = wrapped_flow |> Enum.drop(cycle_size) |> Enum.take(cycle_size)

    leading != [] and repeated != [] and
      mount_cycle?(leading) and
      mount_cycle?(repeated) and
      Enum.map(leading, &semantic_key_without_role/1) ==
        Enum.map(repeated, &semantic_key_without_role/1)
  end

  defp mount_cycle?([%{step: first, role: role} | _] = cycle) do
    first.kind == :entry and first.focus_node_id == first.node_id and role == :framework_mount and
      Enum.any?(cycle, fn %{step: step} ->
        step.node_id != first.node_id and
          step.kind in [:read, :action_execute, :create, :update, :destroy]
      end)
  end

  defp mount_cycle?(_cycle), do: false

  defp classify_role(step, lookup) do
    capture_origin = ActionSemantics.normalize_action_name(Map.get(step, :capture_origin))
    type = ActionSemantics.normalize_atom(Map.get(step, :type), :reaction)
    kind = ActionSemantics.normalize_atom(Map.get(step, :kind), :observation)

    cond do
      capture_origin == "live_view_mount" ->
        :framework_mount

      capture_origin == "automatic" and (type == :observation or kind == :read) ->
        :test_observation

      page_node?(Map.get(step, :node_id), lookup) and kind == :entry ->
        :framework_mount

      true ->
        :app_behavior
    end
  end

  defp semantic_key_without_role(%{step: step}) do
    {
      Map.get(step, :type),
      Map.get(step, :kind),
      ActionSemantics.normalize_action_name(Map.get(step, :action)),
      Map.get(step, :focus_node_id) || Map.get(step, :node_id),
      Map.get(step, :node_id)
    }
  end
end
