defmodule Foundry.PageMetadata do
  @moduledoc """
  Shared page metadata inference for LiveView modules.

  This keeps route, subtype, feature flag, and action inference consistent
  between `Foundry.Context.Introspector` and SparkMeta analyzers.
  """

  @type route_info :: %{path: String.t(), dynamic: boolean()} | nil

  @spec analyze(module(), route_info()) :: map()
  def analyze(module, route_info \\ nil) do
    ast = source_ast(module)

    {page_route, page_dynamic} = resolve_route(module, ast, route_info)

    %{
      page_route: page_route,
      page_dynamic: page_dynamic,
      page_group: attribute_value(module, ast, :page_group),
      page_subtype: page_subtype(module),
      calls_actions: calls_actions(module, ast),
      feature_flags: feature_flags(module, ast)
    }
  end

  @spec calls_actions(module()) :: [map()]
  def calls_actions(module) do
    calls_actions(module, source_ast(module))
  end

  defp resolve_route(_module, _ast, %{path: path, dynamic: dynamic}) do
    {path, dynamic}
  end

  defp resolve_route(module, ast, nil) do
    case attribute_value(module, ast, :page_route) do
      route when is_binary(route) ->
        {route, String.contains?(route, ":")}

      _ ->
        case infer_route_from_source(ast) do
          route when is_binary(route) -> {route, String.contains?(route, ":")}
          _ -> {nil, false}
        end
    end
  end

  defp page_subtype(module) do
    case module_attribute(module, :page_subtype) do
      nil -> detect_sdui_subtype(module)
      subtype -> subtype
    end
  end

  defp detect_sdui_subtype(module) do
    try do
      if function_exported?(module, :__sdui_lookup__, 0) do
        :sdui
      else
        nil
      end
    rescue
      _ -> nil
    end
  end

  defp feature_flags(module, ast) do
    case attribute_value(module, ast, :feature_flags) do
      nil -> []
      flags when is_list(flags) -> flags
      flag -> [flag]
    end
  end

  defp calls_actions(module, ast) do
    scanned = extract_ash_calls(ast)
    annotated = annotated_calls_actions(module, ast)

    merge_actions(scanned, annotated)
  end

  defp annotated_calls_actions(module, ast) do
    case attribute_value(module, ast, :calls_actions) do
      nil -> []
      attrs when is_list(attrs) -> normalize_calls_actions(attrs)
      _ -> normalize_calls_actions(List.wrap(module_attribute(module, :calls_actions)))
    end
  end

  defp merge_actions(scanned, annotated) do
    (scanned ++ annotated)
    |> Enum.uniq_by(fn action ->
      {Map.get(action, "resource"), Map.get(action, "action"), Map.get(action, "action_name")}
    end)
  end

  defp normalize_calls_actions(attrs) do
    Enum.flat_map(attrs, fn
      {resource_module, action_type}
      when is_atom(resource_module) and is_atom(action_type) and
             action_type not in [true, false, nil] ->
        action_name =
          case action_type do
            :create -> "create"
            :read -> "read"
            other -> Atom.to_string(other)
          end

        [
          %{
            "resource" => format_module(resource_module),
            "action" => action_type,
            "action_name" => action_name
          }
        ]

      map when is_map(map) ->
        [map]

      _ ->
        []
    end)
  end

  defp infer_route_from_source(nil), do: nil

  defp infer_route_from_source(ast) do
    case sdui_lookup(ast) do
      {:static, "home"} -> "/"
      {:static, name} when is_binary(name) -> "/" <> name
      _ -> nil
    end
  end

  defp sdui_lookup(ast) do
    ast
    |> collect_sdui_lookup()
    |> List.first()
    |> decode_value()
  end

  defp collect_sdui_lookup({:defmodule, _, [{:__aliases__, _, _}, [do: body]]}) do
    collect_sdui_lookup(body)
  end

  defp collect_sdui_lookup({:use, _, [{:__aliases__, _, [:AshSDUI]}, opts]}) when is_list(opts) do
    opts
    |> Keyword.get(:lookup)
    |> List.wrap()
  end

  defp collect_sdui_lookup(list) when is_list(list) do
    Enum.flat_map(list, &collect_sdui_lookup/1)
  end

  defp collect_sdui_lookup({_, _, args}) when is_list(args) do
    Enum.flat_map(args, &collect_sdui_lookup/1)
  end

  defp collect_sdui_lookup(_), do: []

  defp attribute_value(module, ast, attr_name) do
    case attribute_from_source(ast, attr_name) do
      nil -> module_attribute(module, attr_name)
      value -> value
    end
  end

  defp attribute_from_source(nil, _attr_name), do: nil

  defp attribute_from_source(ast, attr_name) do
    ast
    |> collect_attribute(attr_name)
    |> List.first()
    |> decode_value()
  end

  defp collect_attribute({:defmodule, _, [{:__aliases__, _, _}, [do: body]]}, attr_name) do
    collect_attribute(body, attr_name)
  end

  defp collect_attribute({:@, _, [{name, _, [value]}]}, attr_name) when name == attr_name do
    [value]
  end

  defp collect_attribute(list, attr_name) when is_list(list) do
    Enum.flat_map(list, &collect_attribute(&1, attr_name))
  end

  defp collect_attribute({_, _, args}, attr_name) when is_list(args) do
    Enum.flat_map(args, &collect_attribute(&1, attr_name))
  end

  defp collect_attribute(_, _), do: []

  defp module_attribute(module, attr_name) do
    try do
      module.__info__(:attributes)
      |> Keyword.get(attr_name)
      |> case do
        nil -> nil
        [value] -> value
        value -> value
      end
    rescue
      _ -> nil
    end
  end

  defp source_ast(module) do
    case source_file(module) do
      nil ->
        nil

      path ->
        path
        |> File.read!()
        |> Code.string_to_quoted!()
    end
  rescue
    _ -> nil
  end

  defp source_file(module) do
    try do
      module.__info__(:compile)
      |> Keyword.get(:source)
      |> then(&if(&1, do: to_string(&1), else: nil))
    rescue
      _ -> nil
    end
  end

  defp extract_ash_calls(nil), do: []

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

  defp collect_calls(
         {{:., _, [{:__aliases__, _, [:Ash]}, action]}, _,
          [{:__aliases__, _, module_parts}, named_action | _]}
       )
       when action in [:create, :create!, :update, :update!, :destroy, :destroy!] and
              is_atom(named_action) and named_action not in [true, false, nil] do
    module = Module.concat(module_parts)

    [
      %{
        "resource" => format_module(module),
        "action" => :write,
        "action_name" => Atom.to_string(named_action)
      }
    ]
  end

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
      if action in [:create, :create!, :update, :update!, :destroy, :destroy!],
        do: :write,
        else: :read

    default_action_name =
      cond do
        action in [:create, :create!] -> "create"
        action in [:update, :update!] -> "update"
        action in [:destroy, :destroy!] -> "destroy"
        true -> "read"
      end

    module = Module.concat(module_parts)

    [
      %{
        "resource" => format_module(module),
        "action" => action_type,
        "action_name" => default_action_name
      }
    ]
  end

  defp collect_calls({:|>, _, [lhs, rhs]}) do
    case {leading_module_alias(lhs), rhs} do
      {module_parts, {{:., _, [{:__aliases__, _, [:Ash]}, action]}, _, _args}}
      when action in [:read, :read!, :read_one, :read_one!, :get, :get!] and module_parts != nil ->
        module = Module.concat(module_parts)

        [
          %{
            "resource" => format_module(module),
            "action" => :read,
            "action_name" => "read"
          }
        ]

      {module_parts, {{:., _, [{:__aliases__, _, [:Ash]}, action]}, _, _args}}
      when action in [:create, :create!, :update, :update!, :destroy, :destroy!] and
             module_parts != nil ->
        module = Module.concat(module_parts)

        action_name =
          cond do
            action in [:create, :create!] -> "create"
            action in [:update, :update!] -> "update"
            action in [:destroy, :destroy!] -> "destroy"
          end

        [
          %{
            "resource" => format_module(module),
            "action" => :write,
            "action_name" => action_name
          }
        ]

      _ ->
        collect_calls(lhs) ++ collect_calls(rhs)
    end
  end

  defp collect_calls(
         {{:., _, [{:__aliases__, _, [:Ash, :Changeset]}, action]}, _,
          [{:__aliases__, _, module_parts}, named_action | _]}
       )
       when action in [:for_create, :for_update, :for_destroy] and is_atom(named_action) do
    module = Module.concat(module_parts)

    action_name = named_action |> to_string()

    [
      %{
        "resource" => format_module(module),
        "action" => :write,
        "action_name" => action_name
      }
    ]
  end

  defp collect_calls(
         {{:., _, [{:__aliases__, _, [:Ash, :Query]}, :for_read]}, _,
          [{:__aliases__, _, module_parts}, named_action | _]}
       )
       when is_atom(named_action) do
    module = Module.concat(module_parts)

    [
      %{
        "resource" => format_module(module),
        "action" => :read,
        "action_name" => to_string(named_action)
      }
    ]
  end

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

  defp leading_module_alias({:|>, _, [lhs, _rhs]}), do: leading_module_alias(lhs)
  defp leading_module_alias({:__aliases__, _, parts}), do: parts
  defp leading_module_alias(_), do: nil

  defp decode_value(nil), do: nil

  defp decode_value(value)
       when is_binary(value) or is_atom(value) or is_number(value) or is_boolean(value), do: value

  defp decode_value({:__aliases__, _, parts}) when is_list(parts) do
    Module.concat(parts)
  end

  defp decode_value({:{}, _, values}) when is_list(values) do
    values
    |> Enum.map(&decode_value/1)
    |> List.to_tuple()
  end

  defp decode_value({left, right}) do
    {decode_value(left), decode_value(right)}
  end

  defp decode_value(list) when is_list(list) do
    Enum.map(list, &decode_value/1)
  end

  defp decode_value(_), do: nil

  defp format_module(module) when is_atom(module) do
    module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp format_module(module), do: module
end
