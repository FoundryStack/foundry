defmodule Foundry.SparkMeta.Analyzers.LiveViewActions do
  @moduledoc """
  Scans LiveView module source to infer Ash action calls.

  Uses AST analysis to find patterns like:
  - `Ash.read(Module, ...)`
  - `Ash.create(Module, ...)`
  - `Module |> Ash.read(...)`

  Falls back to `@calls_actions` module attribute if present.
  """

  @doc """
  Extract Ash action calls from a LiveView module.

  Returns a list of maps with `resource` and `action` keys:
  - `resource` is the Ash resource module name (string) being acted upon
  - `action` is `:read` or `:write` (or specific action name)

  Prioritizes AST scanning for actual Ash calls. Falls back to `@calls_actions`
  attribute if no calls are found via AST analysis (allows manual override).
  """
  @spec analyze(module()) :: [map()]
  def analyze(mod) do
    scanned = scan_for_ash_calls(mod)

    # Prefer AST-scanned results; only use @calls_actions if scanning found nothing
    if Enum.any?(scanned) do
      scanned
    else
      case module_attribute(mod, :calls_actions) do
        nil -> []
        attrs when is_list(attrs) -> normalize_calls_actions(attrs)
      end
    end
  end

  defp normalize_calls_actions(attrs) do
    Enum.map(attrs, fn
      {resource_module, action_type} when is_atom(resource_module) ->
        %{
          "resource" => format_module(resource_module),
          "action" => action_type
        }

      map when is_map(map) ->
        map

      other ->
        other
    end)
  end

  defp module_attribute(mod, attr_name) do
    try do
      mod.__info__(:attributes)
      |> Keyword.get(attr_name)
    rescue
      _ -> nil
    end
  end

  defp scan_for_ash_calls(mod) do
    case source_file(mod) do
      nil ->
        []

      path ->
        path
        |> File.read!()
        |> Code.string_to_quoted!()
        |> extract_ash_calls()
    end
  rescue
    _ -> []
  end

  defp source_file(mod) do
    try do
      mod.__info__(:compile)
      |> Keyword.get(:source)
      |> then(&if(&1, do: to_string(&1), else: nil))
    rescue
      _ -> nil
    end
  end

  defp extract_ash_calls(ast) do
    ast
    |> collect_calls()
    |> Enum.uniq()
  end

  defp collect_calls({:defmodule, _, [{:__aliases__, _, _module}, [do: body]]}) do
    collect_calls(body)
  end

  defp collect_calls({:def, _, [{_name, _, _args}, [do: body]]}) do
    collect_calls(body)
  end

  defp collect_calls({:defp, _, [{_name, _, _args}, [do: body]]}) do
    collect_calls(body)
  end

  # Match: Ash.read(Module, ...) or Ash.create(Module, ...) or Ash.read_one!(Module, ...) etc.
  defp collect_calls(
         {{:., _, [{:__aliases__, _, [:Ash]}, action]}, _, [{:__aliases__, _, module_parts} | _]}
       )
       when action in [
              :read,
              :read!,
              :read_one,
              :read_one!,
              :get,
              :get!,
              :create,
              :create!,
              :update,
              :update!,
              :destroy,
              :destroy!
            ] do
    action_type =
      if action in [:create, :create!, :update, :update!, :destroy, :destroy!], do: :write, else: :read
    module = Module.concat(module_parts)
    [%{"resource" => format_module(module), "action" => action_type}]
  end

  # Match: Module |> Ash.read(...) - pipe expression
  defp collect_calls({:|>, _, [_lhs, rhs]}) do
    collect_calls(rhs)
  end

  # Fallback: recurse on all nested terms
  defp collect_calls(term) when is_list(term) do
    Enum.flat_map(term, &collect_calls/1)
  end

  defp collect_calls({_, _, args}) when is_list(args) do
    Enum.flat_map(args, &collect_calls/1)
  end

  defp collect_calls({_, _, args}) when is_tuple(args) do
    collect_calls(Tuple.to_list(args))
  end

  defp collect_calls(_), do: []

  defp format_module(module) when is_atom(module) do
    module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp format_module(module), do: module
end
