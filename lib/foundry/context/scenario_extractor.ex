defmodule Foundry.Context.ScenarioExtractor do
  @moduledoc """
  Extracts BDD scenarios from ExUnit test files via AST parsing.

  Walks test files looking for `describe` blocks with `@moduletag` annotations
  declaring scenario metadata (category, nodes, graph_path, steps, compliance_links).

  Returns a list of `ScenarioEntry` structs.
  """

  alias Foundry.Context.ScenarioEntry

  def extract(project_root, nodes_map) do
    test_dir = Path.join(project_root, "test")

    case File.dir?(test_dir) do
      true ->
        test_dir
        |> Path.join("**/*.{exs,ex}")
        |> Path.wildcard()
        |> Enum.flat_map(&extract_file(&1, project_root, nodes_map))

      false ->
        []
    end
  end

  defp extract_file(file_path, project_root, nodes_map) do
    case File.read(file_path) do
      {:ok, content} ->
        parse_scenarios(content, file_path, project_root, nodes_map)

      {:error, _} ->
        []
    end
  end

  defp parse_scenarios(content, file_path, _project_root, nodes_map) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        source_module = extract_module_name(ast)
        extract_from_ast(ast, source_module, file_path, nodes_map)

      {:error, _} ->
        []
    end
  end

  defp extract_module_name({:defmodule, _meta, [{:__aliases__, _am, parts}, _body]}),
    do: Enum.join(parts, ".")

  defp extract_module_name({:__block__, _meta, forms}) do
    # When file starts with Code.require_file or other statements, AST is wrapped in __block__
    forms
    |> Enum.find_value(fn form ->
      case form do
        {:defmodule, _, [{:__aliases__, _, parts}, _]} -> Enum.join(parts, ".")
        _ -> nil
      end
    end)
    |> Kernel.||("UnknownModule")
  end

  defp extract_module_name(_), do: "UnknownModule"

  defp extract_from_ast(ast, source_module, file_path, nodes_map) do
    Macro.prewalk(ast, [], fn node, acc ->
      case node do
        {:describe, _meta, [name, [do: body]]} ->
          scenarios = extract_scenarios_from_describe(name, body, source_module, file_path, nodes_map)
          {node, acc ++ scenarios}

        {:describe, _meta, [name, body]} ->
          scenarios = extract_scenarios_from_describe(name, body, source_module, file_path, nodes_map)
          {node, acc ++ scenarios}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
  end

  defp extract_scenarios_from_describe(describe_name, body, source_module, file_path, nodes_map) do
    tags = extract_tags_from_body(body)

    # Only create scenario if at least category is declared
    case Keyword.get(tags, :category) do
      nil ->
        []

      category ->
        [
          build_scenario_entry(
            describe_name,
            category,
            tags,
            source_module,
            file_path,
            nodes_map
          )
        ]
    end
  end

  defp extract_tags_from_body(body) do
    Macro.prewalk(body, [], fn node, acc ->
      case node do
        {:@, _meta, [{:moduletag, _m, [values]}]} when is_list(values) ->
          {node, acc ++ values}

        {:@, _meta, [{:moduletag, _m, [value]}]} ->
          {node, acc ++ [value]}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
    |> normalize_tags()
  end

  defp normalize_tags(tags) do
    Enum.reduce(tags, [], fn tag, acc ->
      case tag do
        {key, value} -> acc ++ [{key, value}]
        atom when is_atom(atom) -> acc ++ [{atom, true}]
        _ -> acc
      end
    end)
  end

  defp build_scenario_entry(describe_name, category, tags, source_module, file_path, nodes_map) do
    nodes = get_nodes(tags, file_path, nodes_map)

    graph_path =
      case Keyword.get(tags, :graph_path) do
        nil ->
          nodes

        raw_path when is_list(raw_path) ->
          raw_path
          |> Enum.map(&stringify/1)
          |> Enum.map(&resolve_node_id(&1, nodes_map))

        raw_path ->
          [raw_path]
          |> Enum.map(&stringify/1)
          |> Enum.map(&resolve_node_id(&1, nodes_map))
      end

    compliance_links = Keyword.get(tags, :compliance_links, [])
    steps = Keyword.get(tags, :steps, %{given: [], when: [], then: []})

    # Normalize steps to map if it comes in as a tuple
    steps =
      case steps do
        %{} -> steps
        _ -> %{given: [], when: [], then: []}
      end

    id = generate_scenario_id(source_module, describe_name)

    # Filter tags to only include JSON-serializable atoms
    clean_tags = Enum.filter(tags, fn
      atom when is_atom(atom) -> true
      _ -> false
    end)

    %ScenarioEntry{
      id: id,
      name: describe_name,
      category: category,
      source_file: file_path,
      source_module: source_module,
      nodes: nodes,
      graph_path: graph_path,
      compliance_links: compliance_links,
      steps: steps,
      tags: clean_tags
    }
  end

  defp get_nodes(tags, file_path, nodes_map) do
    case Keyword.get(tags, :nodes) do
      nil ->
        # Fallback: extract from file aliases
        extract_nodes_from_file(file_path, nodes_map)

      nodes when is_list(nodes) ->
        nodes
        |> Enum.map(&stringify/1)
        |> Enum.map(&resolve_node_id(&1, nodes_map))

      node ->
        [stringify(node)]
        |> Enum.map(&resolve_node_id(&1, nodes_map))
    end
  end

  defp resolve_node_id(name, nodes_ref) do
    node_ids = node_ids(nodes_ref)

    cond do
      name in node_ids ->
        name

      true ->
        case resolve_by_suffix(name, node_ids) do
          nil -> name
          resolved -> resolved
        end
    end
  end

  defp resolve_by_suffix(shorthand, node_ids) do
    shorthand_with_separator = "." <> shorthand

    node_ids
    |> Enum.filter(&String.ends_with?(&1, shorthand_with_separator))
    |> case do
      [resolved] -> resolved
      _ -> nil
    end
  end

  defp node_ids(nodes_ref) when is_map(nodes_ref) do
    nodes_ref
    |> Enum.flat_map(fn
      {key, %{id: id, module: module}} -> [to_string(key), id, module]
      {key, %{id: id}} -> [to_string(key), id]
      {key, %{module: module}} -> [to_string(key), module]
      {key, _value} -> [to_string(key)]
    end)
    |> Enum.uniq()
  end

  defp node_ids(nodes_ref) when is_list(nodes_ref) do
    nodes_ref
    |> Enum.flat_map(fn
      %{id: id, module: module} -> [id, module]
      %{id: id} -> [id]
      %{module: module} -> [module]
      value when is_binary(value) -> [value]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp node_ids(_), do: []

  defp extract_nodes_from_file(file_path, nodes_map) do
    case File.read(file_path) do
      {:ok, content} ->
        extract_aliases_from_content(content, nodes_map)

      {:error, _} ->
        []
    end
  end

  defp extract_aliases_from_content(content, nodes_map) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        Macro.prewalk(ast, [], fn node, acc ->
          case node do
            {:alias, _meta, [{:__aliases__, _am, parts}]} ->
              module_name = Enum.join(parts, ".")
              {node, [module_name | acc]}

            _ ->
              {node, acc}
          end
        end)
        |> elem(1)
        |> Enum.uniq()
        |> Enum.filter(&is_in_graph(&1, nodes_map))

      {:error, _} ->
        []
    end
  end

  defp is_in_graph(module_name, nodes_map) do
    module_name in node_ids(nodes_map)
  end

  defp stringify(value) do
    case value do
      atom when is_atom(atom) -> to_string(atom)
      string when is_binary(string) -> string
      _ -> to_string(value)
    end
  end

  defp generate_scenario_id(source_module, describe_name) do
    module_short = source_module |> String.split(".") |> List.last()
    describe_slug = describe_name |> String.downcase() |> String.replace(~r/[^\w]+/, "_")
    "#{module_short}.#{describe_slug}"
  end
end
