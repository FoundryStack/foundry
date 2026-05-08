defmodule ExTracer.ModuleIndex do
  @moduledoc false

  @module Foundry.Context.Scenarios.ModuleIndex

  def resolve_optional_node_id(node_name, lookup),
    do: maybe_apply(:resolve_optional_node_id, [node_name, lookup])

  def normalize_focus_override(focus_value, node_id, lookup),
    do: maybe_apply(:normalize_focus_override, [focus_value, node_id, lookup])

  def resolve_step_focus(node_id, step_name, lookup),
    do: maybe_apply(:resolve_step_focus, [node_id, step_name, lookup])

  def entry_point_level(entry_point, lookup),
    do: maybe_apply(:entry_point_level, [entry_point, lookup])

  def explicit_focus_targets(step, lookup),
    do: maybe_apply(:explicit_focus_targets, [step, lookup]) || []

  defp maybe_apply(fun, args) do
    if Code.ensure_loaded?(@module) and function_exported?(@module, fun, length(args)) do
      apply(@module, fun, args)
    end
  end
end
