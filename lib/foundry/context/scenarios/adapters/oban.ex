defmodule Foundry.Context.Scenarios.Adapters.Oban do
  @moduledoc false

  @behaviour ExTracer.Adapter

  alias ExTracer.FlowExpander
  alias ExTracer.FlowSummary
  alias Foundry.Context.Scenarios.ModuleIndex
  alias Foundry.Context.Scenarios.Utils

  @ash_funs ~w(get read read_one create update destroy)a
  @ash_changeset_funs ~w(for_create for_update for_read for_destroy)a

  @impl true
  def expand_step(step, lookup) do
    case Map.get(lookup.by_id, step.node_id || "") do
      %{type: "job"} = node ->
        if String.ends_with?(step.module_function || "", ".perform") do
          expand_job_step(step, node, lookup)
        else
          []
        end

      _ ->
        []
    end
  end

  @impl true
  def classify_call(module_ast, fun, args, alias_map, lookup, opts) do
    Foundry.Context.Scenarios.CallClassifier.classify_ast_call(
      module_ast,
      fun,
      args,
      alias_map,
      lookup,
      opts
    )
  end

  @impl true
  def focus_for_helper(module_name, helper_name, lookup) do
    with {:ok, module_ast, alias_map} <- ModuleIndex.fetch_module_ast(module_name, lookup),
         {:ok, body} <- ModuleIndex.find_function_body(module_ast, helper_name) do
      Macro.prewalk(body, nil, fn
        {:|>, _, [left, {{:., _, [{:__aliases__, _, [:Ash, :Changeset]}, fun]}, _, args}]} = node,
        nil
        when fun in @ash_changeset_funs ->
          focus =
            left
            |> ModuleIndex.resolve_module_name(alias_map)
            |> ModuleIndex.resolve_optional_node_id(lookup)

          {node, focus || helper_focus_from_args(args || [], alias_map, lookup)}

        {:|>, _, [left, {{:., _, [{:__aliases__, _, [:Ash]}, fun]}, _, args}]} = node, nil
        when fun in @ash_funs ->
          focus =
            left
            |> ModuleIndex.resolve_module_name(alias_map)
            |> ModuleIndex.resolve_optional_node_id(lookup)

          {node, focus || helper_focus_from_args(args || [], alias_map, lookup)}

        {{:., _, [{:__aliases__, _, [:Ash, :Changeset]}, fun]}, _, [resource_ast | _rest]} = node,
        nil
        when fun in @ash_changeset_funs ->
          focus =
            resource_ast
            |> ModuleIndex.resolve_module_name(alias_map)
            |> ModuleIndex.resolve_optional_node_id(lookup)

          {node, focus}

        {{:., _, [{:__aliases__, _, [:Ash]}, fun]}, _, [resource_ast | _rest]} = node, nil
        when fun in @ash_funs ->
          focus =
            resource_ast
            |> ModuleIndex.resolve_module_name(alias_map)
            |> ModuleIndex.resolve_optional_node_id(lookup)

          {node, focus}

        {{:., _, [{:__aliases__, _, [:Oban]}, :insert]}, _, [job_ast]} = node, nil ->
          focus =
            case job_ast do
              {{:., _, [module_ast, :new]}, _, _args} ->
                module_ast
                |> ModuleIndex.resolve_module_name(alias_map)
                |> ModuleIndex.resolve_optional_node_id(lookup)

              _ ->
                nil
            end

          {node, focus}

        node, acc ->
          {node, acc}
      end)
      |> elem(1)
      |> Utils.base_node_id()
    end
  end

  defp expand_job_step(step, node, lookup) do
    with {:ok, module_ast, _alias_map} <- ModuleIndex.fetch_module_ast(node.module, lookup) do
      case ModuleIndex.find_function_body(module_ast, :perform) do
        {:ok, body} ->
          if shallow_stub_body?(body) do
            [
              FlowSummary.expanded_step(step, %{
                type: :reaction,
                kind: :job_execute,
                status: :potential,
                label: "Job implementation is stubbed",
                details: "Job implementation is stubbed",
                source_snippet: Utils.ast_to_text(body)
              })
              | FlowExpander.maybe_assert_result_step(step)
            ]
          else
            FlowExpander.maybe_assert_result_step(step)
          end

        :error ->
          FlowExpander.maybe_assert_result_step(step)
      end
    else
      _ -> FlowExpander.maybe_assert_result_step(step)
    end
  end

  defp helper_focus_from_args([resource_ast | _rest], alias_map, lookup) do
    resource_ast
    |> ModuleIndex.resolve_module_name(alias_map)
    |> ModuleIndex.resolve_optional_node_id(lookup)
  end

  defp helper_focus_from_args(_args, _alias_map, _lookup), do: nil

  defp shallow_stub_body?(:ok), do: true
  defp shallow_stub_body?({:__block__, _, [:ok]}), do: true
  defp shallow_stub_body?(_), do: false
end
