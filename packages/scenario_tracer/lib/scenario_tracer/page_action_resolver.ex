defmodule ScenarioTracer.PageActionResolver do
  @moduledoc false

  alias ExTracer.ActionSemantics

  def resolve_step(step, page_node_id, lookup) when is_binary(page_node_id) do
    with %{calls_actions: calls_actions} when is_list(calls_actions) <-
           Map.get(lookup.by_id, page_node_id),
         step_action_type when is_binary(step_action_type) <-
           ActionSemantics.step_action_type(step),
         [match] <- Enum.filter(calls_actions, &action_match?(&1, step, step_action_type)) do
      action_name =
        ActionSemantics.normalize_action_name(
          Map.get(match, "action_name") || Map.get(match, "action")
        )

      %{
        step
        | action: step.action || action_name,
          focus_node_id:
            ActionSemantics.infer_focus_node_id(
              step.focus_node_id,
              step.node_id,
              action_name,
              lookup
            )
      }
    else
      _ -> step
    end
  end

  def resolve_step(step, _page_node_id, _lookup), do: step

  defp action_match?(action_meta, step, step_action_type) do
    action_resource = Map.get(action_meta, "resource") || Map.get(action_meta, :resource)
    generic_action = Map.get(action_meta, "action") || Map.get(action_meta, :action)
    action_name = Map.get(action_meta, "action_name") || Map.get(action_meta, :action_name)

    action_resource == step.node_id and
      (ActionSemantics.normalize_action_name(action_name) == step_action_type or
         ActionSemantics.normalize_action_name(generic_action) == step_action_type)
  end
end
