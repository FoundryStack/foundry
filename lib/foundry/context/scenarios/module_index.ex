defmodule Foundry.Context.Scenarios.ModuleIndex do
  @moduledoc false

  alias Foundry.Context.Scenarios.Lookup
  alias Foundry.Context.Scenarios.Utils

  @code_globs ["lib/**/*.{ex,exs}", "apps/*/lib/**/*.{ex,exs}"]

  def build(nodes, project_root, runtime_lookup) do
    code_lookup = build_code_lookup(project_root)
    by_id = Map.new(nodes, &{&1.id, &1})

    aliases =
      nodes
      |> Enum.flat_map(fn node ->
        module_name = node.module || node.id
        parts = String.split(module_name, ".")
        short = List.last(parts)
        domain_short = parts |> Enum.take(-2) |> Enum.join(".")
        id_short = node.id |> String.replace_prefix((List.first(parts) || "") <> ".", "")

        [
          {module_name, node.id},
          {node.id, node.id},
          {short, node.id},
          {domain_short, node.id},
          {id_short, node.id}
        ]
      end)
      |> Enum.reject(fn {key, _value} -> is_nil(key) or key == "" end)
      |> Enum.into(%{})

    %Lookup{by_id: by_id, aliases: aliases, code: code_lookup, runtime: runtime_lookup}
  end

  def build_code_lookup(project_root) do
    @code_globs
    |> Enum.flat_map(&Path.wildcard(Path.join(project_root, &1)))
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn file_path, acc ->
      with {:ok, content} <- File.read(file_path),
           {:ok, ast} <- Code.string_to_quoted(content) do
        alias_map = extract_alias_map(ast)

        extract_modules(ast)
        |> Enum.reduce(acc, fn {module_name, module_ast}, inner ->
          Map.put(inner, module_name, %{
            ast: module_ast,
            alias_map: alias_map,
            file: file_path,
            source: content
          })
        end)
      else
        _ -> acc
      end
    end)
  end

  def extract_alias_map(ast) do
    Macro.prewalk(ast, %{}, fn
      {:alias, _meta, args} = node, acc ->
        {node, merge_alias_map(acc, alias_entries_from_ast(args))}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  def extract_module_name({:defmodule, _meta, [{:__aliases__, _am, parts}, _body]}),
    do: Enum.join(parts, ".")

  def extract_module_name({:__block__, _meta, forms}) do
    forms
    |> Enum.find_value(fn
      {:defmodule, _, [{:__aliases__, _, parts}, _]} -> Enum.join(parts, ".")
      _ -> nil
    end)
    |> Kernel.||("UnknownModule")
  end

  def extract_module_name(_), do: "UnknownModule"

  def resolve_module_name({:__aliases__, _, parts}, alias_map) do
    parts
    |> Enum.map(&to_string/1)
    |> resolve_alias_parts(alias_map)
  end

  def resolve_module_name(atom, _alias_map) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  def resolve_module_name(binary, _alias_map) when is_binary(binary), do: binary
  def resolve_module_name(_, _alias_map), do: nil

  def resolve_node_id(nil, _lookup), do: nil

  def resolve_node_id(node_name, %Lookup{} = lookup) do
    normalized = Utils.stringify(node_name)

    cond do
      Map.has_key?(lookup.aliases, normalized) -> Map.fetch!(lookup.aliases, normalized)
      Map.has_key?(lookup.by_id, normalized) -> normalized
      true -> nil
    end
  end

  def resolve_optional_node_id(nil, _lookup), do: nil
  def resolve_optional_node_id(node_name, lookup), do: resolve_node_id(node_name, lookup)

  def fetch_module_ast(module_name, %Lookup{} = lookup) do
    case Map.get(lookup.code, module_name) do
      %{ast: ast, alias_map: alias_map} -> {:ok, ast, alias_map}
      _ -> :error
    end
  end

  def find_function_body(module_ast, function_name) do
    Macro.prewalk(module_ast, :error, fn
      {kind, _meta, [{^function_name, _, _args}, [do: body]]} = node, :error
      when kind in [:def, :defp] ->
        {node, {:ok, body}}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  def resolve_step_focus(nil, _step_name, _lookup), do: nil
  def resolve_step_focus(_node_id, nil, _lookup), do: nil

  def resolve_step_focus(node_id, step_name, %Lookup{} = lookup) do
    case Map.get(lookup.by_id, node_id) do
      %{steps: steps} when is_list(steps) ->
        steps
        |> Enum.with_index()
        |> Enum.find_value(fn {step, index} ->
          current_name = Map.get(step, :name) || Map.get(step, "name")

          if Utils.normalize_name(current_name) == Utils.normalize_name(step_name) do
            "#{node_id}:step:#{index}"
          end
        end)

      _ ->
        nil
    end
  end

  def normalize_focus_override(nil, _node_id, _lookup), do: nil

  def normalize_focus_override(focus_value, node_id, %Lookup{} = lookup) do
    graph_id = Utils.stringify(focus_value)

    cond do
      node_id && String.starts_with?(graph_id, ":step:") ->
        "#{node_id}#{graph_id}"

      node_id && String.starts_with?(graph_id, ":action:") ->
        "#{node_id}#{graph_id}"

      String.contains?(graph_id, ":step:") ->
        normalize_graph_suffix(graph_id, ":step:", lookup)

      String.contains?(graph_id, ":action:") ->
        normalize_graph_suffix(graph_id, ":action:", lookup)

      true ->
        resolve_node_id(graph_id, lookup)
    end
  end

  def explicit_focus_targets(step, %Lookup{} = lookup) do
    explicit_targets =
      step
      |> Utils.first_present([:focus_targets, :next_graph_nodes])
      |> Utils.normalize_string_list()

    resolved_explicit_targets =
      explicit_targets
      |> Enum.map(&normalize_focus_override(&1, nil, lookup))
      |> Enum.reject(&is_nil/1)

    step_names =
      step
      |> Utils.first_present([:next_step_names])
      |> Utils.normalize_string_list()

    if step_names == [] do
      resolved_explicit_targets
    else
      base_targets =
        if explicit_targets != [] do
          Enum.map(explicit_targets, &resolve_node_id(&1, lookup))
        else
          step
          |> Utils.first_present([:next_nodes])
          |> Utils.normalize_string_list()
          |> Enum.map(&resolve_node_id(&1, lookup))
        end

      base_targets
      |> Enum.zip(step_names)
      |> Enum.map(fn {next_node_id, step_name} ->
        resolve_step_focus(next_node_id, step_name, lookup) || next_node_id
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  def build_action_focus(node_id, action_name, %Lookup{} = lookup) do
    case Map.get(lookup.by_id, node_id) do
      %{actions: actions} when is_list(actions) ->
        normalized_action = Utils.normalize_name(action_name)

        if Enum.any?(actions, fn action ->
             current = Map.get(action, :name) || Map.get(action, "name")
             Utils.normalize_name(current) == normalized_action
           end) do
          "#{node_id}:action:#{action_name}"
        else
          nil
        end

      _ ->
        nil
    end
  end

  def infer_module_focus(node_id, %{type: type} = node, fun_name, lookup)
      when type in ["resource", "job", "rule"] do
    build_action_focus(node_id, fun_name, lookup) || node.id
  end

  def infer_module_focus(node_id, %{type: type}, fun_name, lookup)
      when type in ["transfer", "reactor"] do
    resolve_step_focus(node_id, fun_name, lookup) || node_id
  end

  def infer_module_focus(node_id, _node, _fun_name, _lookup), do: node_id

  def extract_action_name(action_ast) do
    case Utils.literal_value(action_ast) do
      action when is_atom(action) -> Atom.to_string(action)
      action when is_binary(action) -> action
      _ -> nil
    end
  end

  def find_action(node, action_name) do
    Enum.find(Map.get(node, :actions, []), fn action ->
      Utils.normalize_name(Map.get(action, :name) || Map.get(action, "name")) ==
        Utils.normalize_name(action_name)
    end)
  end

  def pipeline_step_target_node_id(node_id, pipeline_step) do
    Map.get(pipeline_step, :target_resource) ||
      Map.get(pipeline_step, "target_resource") ||
      node_id
  end

  def resolve_pipeline_focus(node_id, pipeline_step, type) do
    step_name = Map.get(pipeline_step, :name) || Map.get(pipeline_step, "name")

    cond do
      is_nil(step_name) ->
        node_id

      type in ["transfer", "reactor"] ->
        "#{node_id}:step:#{Map.get(pipeline_step, :step_index) || Map.get(pipeline_step, "step_index") || 0}"

      true ->
        node_id
    end
  end

  def pipeline_step_kind(pipeline_step) do
    case Map.get(pipeline_step, :step_kind) || Map.get(pipeline_step, "step_kind") do
      :write -> :write
      "write" -> :write
      :read -> :read
      "read" -> :read
      _ -> :action_execute
    end
  end

  def pipeline_step_label(node_id, pipeline_step, description) do
    step_name = Map.get(pipeline_step, :name) || Map.get(pipeline_step, "name")

    cond do
      is_binary(description) and description != "" -> description
      is_atom(step_name) -> "#{List.last(String.split(node_id, "."))}.#{step_name}"
      is_binary(step_name) -> "#{List.last(String.split(node_id, "."))}.#{step_name}"
      true -> "Expand #{List.last(String.split(node_id, "."))}"
    end
  end

  def pipeline_step_description(pipeline_step) do
    Map.get(pipeline_step, :description) || Map.get(pipeline_step, "description")
  end

  def pipeline_step_snippet(pipeline_step) do
    Map.get(pipeline_step, :source_snippet) || Map.get(pipeline_step, "source_snippet")
  end

  def entry_point_level(%{node_id: node_id, module_function: module_function, kind: kind}, lookup) do
    node = Map.get(lookup.by_id, Utils.base_node_id(node_id || ""))

    cond do
      node == nil ->
        case kind do
          kind when kind in [:action_prepare, :action_execute] -> :action
          kind when kind in [:rule_check, :rule_branch] -> :rule
          _ -> nil
        end

      node.type == "trigger" and String.ends_with?(module_function || "", ".handle_webhook") ->
        :webhook

      node.type == "job" and String.ends_with?(module_function || "", ".perform") ->
        :job

      node.type == "transfer" ->
        :transfer

      node.type == "reactor" ->
        :reactor

      node.type == "resource" ->
        :action

      node.type == "rule" ->
        :rule

      true ->
        nil
    end
  end

  defp extract_modules(ast) do
    Macro.prewalk(ast, [], fn
      {:defmodule, _meta, [{:__aliases__, _, parts}, _body]} = node, acc ->
        {node, [{Enum.join(parts, "."), node} | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp alias_entries_from_ast([{:__aliases__, _, base}, [do: {:__block__, _, nested}]]) do
    Enum.flat_map(nested, fn
      {:__aliases__, _, [leaf]} -> [{to_string(leaf), Enum.join(base ++ [leaf], ".")}]
      _ -> []
    end)
  end

  defp alias_entries_from_ast([{:__aliases__, _, parts}]), do: default_alias_entry(parts)

  defp alias_entries_from_ast([{:__aliases__, _, parts}, opts]) when is_list(opts) do
    explicit_alias = Keyword.get(opts, :as)

    if explicit_alias do
      [{alias_name(explicit_alias), Enum.join(parts, ".")}]
    else
      default_alias_entry(parts)
    end
  end

  defp alias_entries_from_ast(_args), do: []
  defp default_alias_entry(parts), do: [{List.last(parts) |> to_string(), Enum.join(parts, ".")}]
  defp alias_name({:__aliases__, _, parts}), do: List.last(parts) |> to_string()
  defp alias_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp alias_name(other), do: to_string(other)
  defp merge_alias_map(left, right), do: Map.merge(left, Map.new(right))

  defp resolve_alias_parts([head | tail], alias_map) do
    case Map.get(alias_map, head) do
      nil -> Enum.join([head | tail], ".")
      resolved when tail == [] -> resolved
      resolved -> Enum.join([resolved | tail], ".")
    end
  end

  defp resolve_alias_parts([], _alias_map), do: nil

  defp normalize_graph_suffix(graph_id, marker, lookup) do
    [base, suffix] = String.split(graph_id, marker, parts: 2)

    case resolve_node_id(base, lookup) do
      nil -> nil
      resolved -> "#{resolved}#{marker}#{suffix}"
    end
  end
end
