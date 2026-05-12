defmodule Foundry.Context.Scenarios.PageTestFlow do
  @moduledoc false

  alias ExTracer.FlowSummary
  alias ExTracer.TestBlock
  alias ExTracer.Utils
  alias Foundry.Context.Scenarios.ModuleIndex

  @page_fixture_actions %{
    "session_for" => {"IgamingRef.Gaming.GameSession", :read, "read"},
    "withdrawal_for_wallet" => {"IgamingRef.Finance.WithdrawalRequest", :read, "read"},
    "transfer_for_wallet" => {"IgamingRef.Finance.Transfer", :read, "read"}
  }

  def infer_static_flow(%TestBlock{} = test_block, alias_map, lookup) do
    test_block.block
    |> collect_events(alias_map, lookup)
    |> Enum.sort_by(fn {line, order, _event} -> {line || test_block.line || 0, order} end)
    |> Enum.flat_map(fn {line, _order, event} ->
      build_event_steps(event, line || test_block.line, test_block, lookup)
    end)
  end

  defp collect_events(ast, alias_map, lookup) do
    {_ast, {_index, events}} =
      Macro.prewalk(ast, {0, []}, fn
        {:live, meta, args} = node, {index, events} ->
          event = infer_live_event(args, meta, lookup)
          {node, {index + 1, maybe_prepend_event(events, meta[:line], index, event)}}

        {{:., meta, [module_ast, fun]}, _call_meta, args} = node, {index, events} ->
          event = infer_remote_event(module_ast, fun, args, alias_map)
          {node, {index + 1, maybe_prepend_event(events, meta[:line], index, event)}}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(events)
  end

  defp maybe_prepend_event(events, _line, _index, nil), do: events

  defp maybe_prepend_event(events, line, index, event) do
    [{line, index, event} | events]
  end

  defp infer_live_event([_conn_ast, route_ast | _rest], _meta, lookup) do
    route_ast
    |> route_from_ast()
    |> resolve_page_node(lookup)
    |> case do
      nil -> nil
      page_node_id -> {:page_mount, page_node_id}
    end
  end

  defp infer_live_event(_, _, _lookup), do: nil

  defp infer_remote_event(module_ast, fun, _args, alias_map) do
    module_name = ModuleIndex.resolve_module_name(module_ast, alias_map)
    helper_name = fun |> to_string() |> String.trim_leading(":")

    cond do
      is_nil(module_name) ->
        nil

      String.ends_with?(module_name, ".PageFixtures") ->
        case Map.get(@page_fixture_actions, helper_name) do
          nil -> nil
          {node_id, kind, action} -> {:fixture_action, node_id, kind, action}
        end

      true ->
        nil
    end
  end

  defp build_event_steps({:page_mount, page_node_id}, line, test_block, lookup) do
    node = Map.get(lookup.by_id, page_node_id)

    page_step =
      FlowSummary.build_step(%{
        type: :entry,
        kind: :action_execute,
        provenance: :expanded,
        label: "Execute #{short_name(page_node_id)}",
        node_id: page_node_id,
        focus_node_id: page_node_id,
        source_snippet: "live(...)",
        details: "Statically inferred from page route",
        line: line,
        test_name: test_block.name,
        test_kind: test_block.kind
      })

    action_steps =
      node
      |> page_actions()
      |> Enum.map(fn action ->
        build_action_step(action, line, test_block, lookup,
          source_snippet: "live(...)",
          details: "Statically inferred from page metadata"
        )
      end)

    [page_step | action_steps]
  end

  defp build_event_steps({:fixture_action, node_id, kind, action}, line, test_block, lookup) do
    [
      build_action_step(
        %{"resource" => node_id, "action" => kind, "action_name" => action},
        line,
        test_block,
        lookup,
        source_snippet: "#{short_name(node_id)} helper",
        details: "Statically inferred from page assertion helper"
      )
    ]
  end

  defp page_actions(nil), do: []
  defp page_actions(node), do: List.wrap(Map.get(node, :calls_actions, []))

  defp build_action_step(action, line, test_block, lookup, opts) do
    node_id = Utils.stringify(Map.get(action, "resource") || Map.get(action, :resource))
    kind = normalize_kind(Map.get(action, "action") || Map.get(action, :action))
    action_name = Utils.stringify(Map.get(action, "action_name") || Map.get(action, :action_name))

    FlowSummary.build_step(%{
      type: if(kind == :read, do: :reaction, else: :entry),
      kind: kind,
      provenance: :expanded,
      label: "Execute #{short_name(node_id)}.#{action_name}",
      node_id: node_id,
      focus_node_id: ModuleIndex.build_action_focus(node_id, action_name, lookup) || node_id,
      action: action_name,
      source_snippet: Keyword.fetch!(opts, :source_snippet),
      details: Keyword.fetch!(opts, :details),
      line: line,
      test_name: test_block.name,
      test_kind: test_block.kind
    })
  end

  defp normalize_kind(kind) when kind in [:read, "read"], do: :read
  defp normalize_kind(kind) when kind in [:write, "write"], do: :write
  defp normalize_kind(_kind), do: :action_execute

  defp resolve_page_node(nil, _lookup), do: nil

  defp resolve_page_node(route, lookup) do
    lookup.by_id
    |> Map.values()
    |> Enum.filter(&(&1.type == "page"))
    |> Enum.find_value(fn node ->
      if route_matches?(route, Map.get(node, :page_route)) do
        node.id
      end
    end)
  end

  defp route_matches?(nil, _page_route), do: false
  defp route_matches?(_route, nil), do: false

  defp route_matches?(route, page_route) do
    route_segments = route_segments(route)
    page_segments = route_segments(page_route)

    length(route_segments) == length(page_segments) and
      Enum.zip(route_segments, page_segments)
      |> Enum.all?(fn {route_segment, page_segment} ->
        route_segment == page_segment or dynamic_segment?(route_segment) or
          dynamic_segment?(page_segment)
      end)
  end

  defp route_segments("/") do
    []
  end

  defp route_segments(route) do
    route
    |> String.trim()
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
  end

  defp dynamic_segment?(segment), do: String.starts_with?(segment, ":")

  defp route_from_ast(ast) do
    case Utils.literal_value(ast) do
      route when is_binary(route) ->
        route

      _ ->
        ast
        |> interpolation_to_route()
        |> normalize_route_text()
    end
  end

  defp interpolation_to_route({:<<>>, _, parts}) when is_list(parts) do
    parts
    |> Enum.map(fn
      part when is_binary(part) -> part
      _ -> ":dynamic"
    end)
    |> Enum.join()
  end

  defp interpolation_to_route(ast), do: Utils.ast_to_text(ast)

  defp normalize_route_text(nil), do: nil

  defp normalize_route_text(route) do
    route
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp short_name(node_id), do: node_id |> String.split(".") |> List.last()
end
