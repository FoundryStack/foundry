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

  alias Foundry.Context.Scenarios.CallClassifier
  alias Foundry.TestScenario.RuntimeCapture

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :scenario, accumulate: true, persist: true)
      import Foundry.TestScenario, only: [capture: 1, capture: 2]
    end
  end

  defmacro capture(do: body) do
    caller = __CALLER__
    describe_name = current_describe_name(caller)
    test_name = current_test_name(caller, describe_name)

    context = %{
      module: caller.module,
      describe: describe_name,
      test: test_name,
      file: caller.file,
      line: caller.line
    }

    instrumented_body = instrument_capture_body(body, caller)

    quote do
      Foundry.TestScenario.__capture__(unquote(Macro.escape(context)), fn ->
        unquote(instrumented_body)
      end)
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
    RuntimeCapture.trace_call(attrs, fun)
  end

  defp current_describe_name(%Macro.Env{} = caller) do
    case Module.get_attribute(caller.module, :ex_unit_describe) do
      {_line, name, _level} -> name
      _ -> nil
    end
  end

  defp current_test_name(%Macro.Env{function: {fun_name, _arity}}, describe_name) do
    fun_name
    |> Atom.to_string()
    |> String.replace_prefix("test ", "")
    |> String.replace_prefix("property ", "")
    |> strip_describe_prefix(describe_name)
  end

  defp instrument_capture_body(body, caller) do
    Macro.prewalk(body, fn
      {:|>, _meta, [left, {{:., _, [module_ast, fun]}, _call_meta, args}]} = pipe_ast ->
        case CallClassifier.runtime_trace_attrs(
               module_ast,
               fun,
               [left | args || []],
               pipe_ast,
               caller
             ) do
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
        case CallClassifier.runtime_trace_attrs(module_ast, fun, args || [], call_ast, caller) do
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

  defp strip_describe_prefix(test_name, nil), do: test_name
  defp strip_describe_prefix(test_name, ""), do: test_name

  defp strip_describe_prefix(test_name, describe_name) do
    String.replace_prefix(test_name, describe_name <> " ", "")
  end
end
