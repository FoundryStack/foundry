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
    graph_path = Keyword.get(tags, :graph_path, nodes)
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
        Enum.map(nodes, &stringify/1)

      node ->
        [stringify(node)]
    end
  end

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
    Enum.any?(nodes_map, fn node -> node.module == module_name end)
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
