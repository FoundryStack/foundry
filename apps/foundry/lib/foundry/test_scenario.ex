defmodule Foundry.TestScenario do
  @moduledoc """
  Lightweight test-side annotations for Studio scenario extraction.

  `@scenario` is intentionally small. Real executable test calls remain the
  primary source of truth; the attribute only adds labels or exact-focus hints
  where code alone is ambiguous.

  `capture/2` automatically records executable entrypoints inside the wrapped
  test body. `trace_node/2` remains available as a compatibility escape hatch
  for flows that cannot yet be inferred automatically.

  Example:

      use Foundry.TestScenario

      @scenario category: :compliance,
                compliance_links: ["RG-UK-014"],
                flow: [
                  %{
                    id: "receive",
                    type: :entry,
                    node: "Finance.WithdrawalWebhook",
                    label: "Validate webhook payload",
                    action: "handle_webhook",
                    focus_targets: ["Finance.WithdrawalWebhookEvent"]
                  }
                ]
  """

  alias Foundry.TestScenario.RuntimeCapture

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :scenario, accumulate: true, persist: true)
      import Foundry.TestScenario, only: [capture: 2, trace_node: 1, trace_node: 2]
    end
  end

  defmacro capture(context, fun_ast) do
    case fun_ast do
      {:fn, _meta, [{:->, _arrow_meta, [[], body]}]} ->
        instrumented_body = instrument_capture_body(body, __CALLER__)

        quote do
          Foundry.TestScenario.__capture__(unquote(context), fn ->
            unquote(instrumented_body)
          end)
        end

      _ ->
        quote do
          Foundry.TestScenario.__capture__(unquote(context), unquote(fun_ast))
        end
    end
  end

  def __capture__(context, fun) when is_map(context) and is_function(fun, 0) do
    RuntimeCapture.capture(context, fun)
  end

  @doc false
  def trace_call(attrs, fun) when is_map(attrs) and is_function(fun, 0) do
    case Map.pop(attrs, :node_id) do
      {node_id, event_attrs} when is_binary(node_id) ->
        trace_node(node_id, event_attrs)

      _ ->
        :ok
    end

    fun.()
  end

  @doc """
  Manually append a scenario runtime event.

  Deprecated for ordinary test authoring. Prefer `capture/2`, which automatically
  records executable entrypoints and lets the extractor expand them through the
  graph without leaking Foundry-specific calls into domain code.
  """
  def trace_node(node_id), do: RuntimeCapture.trace_node(node_id)
  def trace_node(node_id, attrs), do: RuntimeCapture.trace_node(node_id, attrs)

  defp instrument_capture_body(body, caller) do
    Macro.prewalk(body, fn
      {:|>, _meta, [left, {{:., _, [module_ast, fun]}, _call_meta, args}]} = pipe_ast ->
        case infer_trace_attrs(module_ast, fun, [left | args || []], pipe_ast, caller) do
          nil ->
            pipe_ast

          attrs ->
            quote do
              Foundry.TestScenario.trace_call(unquote(Macro.escape(attrs)), fn ->
                unquote(pipe_ast)
              end)
            end
        end

      {{:., _meta, [module_ast, fun]}, _call_meta, args} = call_ast ->
        case infer_trace_attrs(module_ast, fun, args || [], call_ast, caller) do
          nil ->
            call_ast

          attrs ->
            quote do
              Foundry.TestScenario.trace_call(unquote(Macro.escape(attrs)), fn ->
                unquote(call_ast)
              end)
            end
        end

      node ->
        node
    end)
  end

  defp infer_trace_attrs(module_ast, fun, args, call_ast, caller) do
    module_name = resolve_module_name(module_ast, caller)
    fun_name = to_string(fun)

    cond do
      module_name == "Ash" and fun in [:get, :read, :read_one, :create, :update, :destroy] ->
        infer_ash_trace(args, fun_name, call_ast, caller)

      module_name == "Ash.Changeset" and
          fun in [:for_create, :for_update, :for_read, :for_destroy] ->
        infer_changeset_trace(args, fun_name, call_ast, caller)

      module_name == "Reactor" and fun == :run ->
        infer_reactor_trace(args, call_ast, caller)

      is_binary(module_name) ->
        infer_module_trace(module_name, fun_name, call_ast)

      true ->
        nil
    end
  end

  defp infer_ash_trace([resource_ast | rest], fun_name, call_ast, caller) do
    with resource_name when is_binary(resource_name) <- resolve_module_name(resource_ast, caller) do
      action =
        case fun_name do
          "create" -> extract_action_from_keyword(rest)
          "update" -> extract_action_from_args(rest)
          "destroy" -> extract_action_from_args(rest)
          _ -> nil
        end

      {type, kind} =
        case fun_name do
          "get" -> {:observation, :read}
          "read" -> {:observation, :read}
          "read_one" -> {:observation, :read}
          "create" -> {:entry, :action_execute}
          "update" -> {:entry, :action_execute}
          "destroy" -> {:entry, :action_execute}
        end

      build_trace_attrs(resource_name, %{
        type: type,
        kind: kind,
        action: action,
        module_function: "Ash.#{fun_name}",
        source_snippet: Macro.to_string(call_ast),
        focus_node_id: action_focus(resource_name, action)
      })
    else
      _ -> nil
    end
  end

  defp infer_ash_trace(_, _, _, _), do: nil

  defp infer_changeset_trace([resource_ast | rest], fun_name, call_ast, caller) do
    with resource_name when is_binary(resource_name) <- resolve_module_name(resource_ast, caller) do
      action =
        case rest do
          [action_ast | _] -> literal_action_name(action_ast)
          _ -> nil
        end

      build_trace_attrs(resource_name, %{
        type: :entry,
        kind: :action_prepare,
        action: action,
        module_function: "Ash.Changeset.#{fun_name}",
        source_snippet: Macro.to_string(call_ast),
        focus_node_id: action_focus(resource_name, action),
        details: "Only action preparation executed"
      })
    else
      _ -> nil
    end
  end

  defp infer_changeset_trace(_, _, _, _), do: nil

  defp infer_reactor_trace([module_ast | _rest], call_ast, caller) do
    with module_name when is_binary(module_name) <- resolve_module_name(module_ast, caller) do
      build_trace_attrs(module_name, %{
        type: :entry,
        kind: :action_execute,
        module_function: "Reactor.run",
        source_snippet: Macro.to_string(call_ast)
      })
    else
      _ -> nil
    end
  end

  defp infer_reactor_trace(_, _, _), do: nil

  defp infer_module_trace(module_name, fun_name, call_ast) do
    {type, kind, action} =
      cond do
        fun_name == "evaluate" ->
          {:assertion, :rule_check, fun_name}

        fun_name == "handle_webhook" ->
          {:entry, :trigger_receive, fun_name}

        fun_name == "perform" ->
          {:job, :job_execute, fun_name}

        true ->
          {:entry, :action_execute, fun_name}
      end

    build_trace_attrs(module_name, %{
      type: type,
      kind: kind,
      action: action,
      module_function: "#{module_name}.#{fun_name}",
      source_snippet: Macro.to_string(call_ast),
      focus_node_id: action_focus(module_name, action)
    })
  end

  defp build_trace_attrs(node_id, attrs) when is_binary(node_id) do
    attrs
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> Map.put(:node_id, node_id)
    |> Map.put(:capture_origin, :automatic)
  end

  defp action_focus(node_id, nil), do: node_id
  defp action_focus(node_id, action), do: "#{node_id}:action:#{action}"

  defp resolve_module_name(ast, caller) do
    expanded = Macro.expand(ast, caller)

    cond do
      is_atom(expanded) ->
        expanded
        |> Atom.to_string()
        |> String.trim_leading("Elixir.")

      match?({:__aliases__, _, _}, ast) ->
        ast
        |> Macro.to_string()
        |> String.trim_leading("Elixir.")

      true ->
        nil
    end
  end

  defp extract_action_from_keyword(rest) do
    rest
    |> Enum.find_value(fn
      keyword when is_list(keyword) -> Keyword.get(keyword, :action)
      _ -> nil
    end)
    |> literal_action_name()
  end

  defp extract_action_from_args([action_ast | _rest]), do: literal_action_name(action_ast)
  defp extract_action_from_args(_args), do: nil

  defp literal_action_name(value) when is_atom(value), do: Atom.to_string(value)
  defp literal_action_name(value) when is_binary(value), do: value
  defp literal_action_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp literal_action_name(_value), do: nil
end
