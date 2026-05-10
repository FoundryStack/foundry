defmodule ExTracer.ActionSemantics do
  @moduledoc false

  alias ExTracer.Utils

  @normalized_atoms %{
    "entry" => :entry,
    "reaction" => :reaction,
    "assertion" => :assertion,
    "observation" => :observation,
    "command" => :command,
    "event" => :event,
    "job" => :job,
    "action_prepare" => :action_prepare,
    "action_execute" => :action_execute,
    "trigger_receive" => :trigger_receive,
    "job_enqueue" => :job_enqueue,
    "job_execute" => :job_execute,
    "read" => :read,
    "create" => :create,
    "update" => :update,
    "destroy" => :destroy,
    "write" => :write,
    "rule_check" => :rule_check,
    "assert_result" => :assert_result,
    "passed" => :passed,
    "failed" => :failed,
    "short_circuit" => :short_circuit,
    "matched" => :matched
  }

  @kind_action_types %{
    read: "read",
    create: "create",
    update: "update",
    destroy: "destroy",
    write: "create"
  }

  def normalize_atom(nil, default), do: default
  def normalize_atom(value, _default) when is_atom(value), do: value

  def normalize_atom(value, default) when is_binary(value) do
    Map.get(@normalized_atoms, value, default)
  end

  def normalize_atom(value, default) do
    value
    |> Utils.stringify()
    |> normalize_atom(default)
  end

  def normalize_action_name(nil), do: nil
  def normalize_action_name(value), do: value |> Utils.stringify() |> Utils.normalize_name()

  def action_type_from_kind(kind) do
    kind
    |> normalize_atom(nil)
    |> then(&Map.get(@kind_action_types, &1))
  end

  def step_action_type(step) when is_map(step) do
    cond do
      present_action?(Map.get(step, :action)) ->
        normalize_action_name(Map.get(step, :action))

      normalized_type = action_type_from_kind(Map.get(step, :kind)) ->
        normalized_type

      Map.get(step, :type) == :observation ->
        "read"

      true ->
        nil
    end
  end

  def infer_action(node_id, explicit_action, kind, lookup) when is_binary(node_id) do
    case normalize_action_name(explicit_action) do
      nil -> infer_action_name(node_id, action_type_from_kind(kind), lookup)
      action -> action
    end
  end

  def infer_action(_node_id, explicit_action, _kind, _lookup),
    do: normalize_action_name(explicit_action)

  def infer_focus_node_id(existing_focus, node_id, action, lookup) do
    focus =
      existing_focus
      |> Utils.normalize_optional_string()
      |> canonical_graph_node_id()

    cond do
      is_binary(focus) and String.contains?(focus, ":action:") ->
        focus

      present_action?(action) ->
        build_action_focus(node_id || focus, action, lookup) ||
          fallback_focus(node_id, focus, action)

      true ->
        focus || node_id
    end
  end

  def infer_action_name(node_id, action_type, lookup)
      when is_binary(node_id) and is_binary(action_type) do
    with %{actions: actions} when is_list(actions) <- Map.get(lookup.by_id, node_id) do
      actions
      |> Enum.filter(fn action ->
        action
        |> Map.get(:type)
        |> normalize_action_name() == action_type
      end)
      |> case do
        [%{name: name}] -> normalize_action_name(name)
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  def infer_action_name(_node_id, _action_type, _lookup), do: nil

  def build_action_focus(node_id, action_name, lookup)
      when is_binary(node_id) and not is_nil(action_name) do
    normalized_action = normalize_action_name(action_name)

    with %{actions: actions} when is_list(actions) <- Map.get(lookup.by_id, node_id),
         true <-
           Enum.any?(actions, &(normalize_action_name(Map.get(&1, :name)) == normalized_action)) do
      "#{node_id}:action:#{normalized_action}"
    else
      _ -> nil
    end
  end

  def build_action_focus(_node_id, _action_name, _lookup), do: nil

  def canonical_graph_node_id(nil), do: nil

  def canonical_graph_node_id(graph_id) do
    graph_id = Utils.stringify(graph_id)

    cond do
      String.contains?(graph_id, ":action:") ->
        [base, action] = String.split(graph_id, ":action:", parts: 2)
        canonical_graph_node_id(base) <> ":action:" <> normalize_action_name(action)

      String.contains?(graph_id, ":step:") ->
        [base, step] = String.split(graph_id, ":step:", parts: 2)
        canonical_graph_node_id(base) <> ":step:" <> step

      true ->
        String.replace_suffix(graph_id, ".Version", "")
    end
  end

  defp fallback_focus(node_id, focus, action) do
    base = node_id || focus

    if is_binary(base) do
      "#{base}:action:#{normalize_action_name(action)}"
    end
  end

  defp present_action?(value) do
    case normalize_action_name(value) do
      nil -> false
      "" -> false
      _ -> true
    end
  end
end
