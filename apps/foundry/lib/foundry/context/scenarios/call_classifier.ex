defmodule Foundry.Context.Scenarios.CallClassifier do
  @moduledoc false

  alias ExTracer.FlowSummary
  alias Foundry.Context.Scenarios.ModuleIndex
  alias Foundry.Context.Scenarios.Utils

  @ash_funs ~w(get read read_one create update destroy)a
  @ash_changeset_funs ~w(for_create for_update for_read for_destroy)a

  def classify_ast_call(module_ast, fun, args, alias_map, lookup, opts) do
    module_name = ModuleIndex.resolve_module_name(module_ast, alias_map)
    fun_name = to_string(fun)

    cond do
      module_name == "Reactor" and fun == :run ->
        infer_reactor_run_step(args, lookup, opts)

      module_name == "Ash" and fun in @ash_funs ->
        infer_ash_step(fun_name, args, alias_map, lookup, opts)

      module_name == "Ash.Changeset" and fun in @ash_changeset_funs ->
        infer_changeset_step(fun_name, args, alias_map, lookup, opts)

      is_nil(module_name) ->
        nil

      resolved_node = ModuleIndex.resolve_node_id(module_name, lookup) ->
        infer_module_step(module_name, resolved_node, fun_name, lookup, opts)

      true ->
        nil
    end
  end

  def runtime_trace_attrs(module_ast, fun, args, call_ast, caller) do
    module_name = resolve_runtime_module_name(module_ast, caller)
    fun_name = to_string(fun)

    cond do
      module_name == "Ash" and fun in @ash_funs ->
        infer_ash_trace(args, fun_name, call_ast, caller)

      module_name == "Ash.Changeset" and fun in @ash_changeset_funs ->
        infer_changeset_trace(args, fun_name, call_ast, caller)

      module_name == "Reactor" and fun == :run ->
        infer_reactor_trace(args, call_ast, caller)

      true ->
        nil
    end
  end

  def infer_assertion_context(pattern_ast) do
    result = Utils.ast_to_text(pattern_ast)

    %{
      result: result,
      status: infer_status_from_pattern(pattern_ast)
    }
  end

  def extract_ash_action(args) when is_list(args) do
    Enum.reduce_while(args, {nil, []}, fn arg, {action, seen} ->
      cond do
        action_name = ModuleIndex.extract_action_name(arg) ->
          {:halt, {action_name, seen ++ [arg]}}

        action_name = extract_keyword_action(arg) ->
          {:halt, {action_name, seen ++ [arg]}}

        true ->
          {:cont, {action, seen ++ [arg]}}
      end
    end)
  end

  def extract_ash_action(_args), do: {nil, []}

  def ash_kind(fun_name) when fun_name in ["get", "read", "read_one"], do: :read
  def ash_kind(_fun_name), do: :action_execute

  def ash_step_label(fun_name, node_id, action) do
    short = List.last(String.split(node_id, "."))

    case {fun_name, action} do
      {"get", _} -> "Load #{short}"
      {"read", _} -> "Read #{short}"
      {"read_one", _} -> "Read #{short}"
      {"create", nil} -> "Create #{short}"
      {"create", act} -> "Create #{short} via #{act}"
      {"update", nil} -> "Update #{short}"
      {"update", act} -> "Update #{short} via #{act}"
      {"destroy", nil} -> "Destroy #{short}"
      {"destroy", act} -> "Destroy #{short} via #{act}"
      _ -> "#{String.capitalize(fun_name)} #{short}"
    end
  end

  def changeset_step_label(fun_name, node_id, action) do
    short = List.last(String.split(node_id, "."))

    case {fun_name, action} do
      {"for_create", nil} -> "Prepare create #{short}"
      {"for_create", act} -> "Prepare #{short}.#{act}"
      {"for_update", nil} -> "Prepare update #{short}"
      {"for_update", act} -> "Prepare #{short}.#{act}"
      {"for_read", nil} -> "Prepare read #{short}"
      {"for_read", act} -> "Prepare #{short}.#{act}"
      {"for_destroy", nil} -> "Prepare destroy #{short}"
      {"for_destroy", act} -> "Prepare #{short}.#{act}"
      _ -> "Prepare #{short}"
    end
  end

  def infer_module_label(:assertion, short_name, _fun_name), do: "Evaluate #{short_name}"
  def infer_module_label(:job, short_name, _fun_name), do: "Run #{short_name}"
  def infer_module_label(:entry, short_name, "handle_webhook"), do: "Handle #{short_name} webhook"

  def infer_module_label(:entry, short_name, fun_name),
    do: "#{String.capitalize(fun_name)} #{short_name}"

  def infer_module_label(_type, short_name, fun_name),
    do: "#{String.capitalize(fun_name)} #{short_name}"

  defp infer_ash_step(fun_name, [resource_ast | rest], alias_map, lookup, opts) do
    resource_name = ModuleIndex.resolve_module_name(resource_ast, alias_map)
    node_id = ModuleIndex.resolve_node_id(resource_name, lookup)

    if node_id do
      {action, arg_payload} = extract_ash_action(rest)

      focus_node_id =
        if action, do: ModuleIndex.build_action_focus(node_id, action, lookup), else: node_id

      FlowSummary.build_step(%{
        type: if(fun_name in ["get", "read", "read_one"], do: :observation, else: :entry),
        kind: ash_kind(fun_name),
        label: ash_step_label(fun_name, node_id, action),
        node_id: node_id,
        focus_node_id: focus_node_id,
        focus_targets: [],
        emits: [],
        reacts_to: nil,
        action: action,
        actor: nil,
        module_function: "Ash.#{fun_name}",
        source_snippet: Utils.short_call_snippet("Ash", fun_name, arg_payload),
        details: nil,
        line: opts.line,
        test_name: opts.test_name,
        test_kind: opts.test_kind,
        assertion_context: opts.assertion_context
      })
    end
  end

  defp infer_ash_step(_, _, _, _, _), do: nil

  defp infer_reactor_run_step([target_module_ast | _rest] = args, lookup, opts) do
    target_module_name = ModuleIndex.resolve_module_name(target_module_ast, opts.alias_map || %{})
    target_node_id = ModuleIndex.resolve_node_id(target_module_name, lookup)

    if target_node_id do
      infer_module_step(
        target_module_name,
        target_node_id,
        "run",
        lookup,
        %{
          opts
          | assertion_context:
              Map.put(
                opts.assertion_context || %{},
                :source_snippet,
                Utils.short_call_snippet("Reactor", "run", args)
              )
        }
      )
    end
  end

  defp infer_reactor_run_step(_, _, _), do: nil

  defp infer_changeset_step(fun_name, [resource_ast | rest], alias_map, lookup, opts) do
    resource_name = ModuleIndex.resolve_module_name(resource_ast, alias_map)
    node_id = ModuleIndex.resolve_node_id(resource_name, lookup)

    if node_id do
      action =
        case rest do
          [action_ast | _] -> ModuleIndex.extract_action_name(action_ast)
          _ -> nil
        end

      focus_node_id =
        if action, do: ModuleIndex.build_action_focus(node_id, action, lookup), else: node_id

      FlowSummary.build_step(%{
        type: :entry,
        kind: :action_prepare,
        label: changeset_step_label(fun_name, node_id, action),
        node_id: node_id,
        focus_node_id: focus_node_id,
        focus_targets: [],
        emits: [],
        reacts_to: nil,
        action: action,
        actor: nil,
        module_function: "Ash.Changeset.#{fun_name}",
        source_snippet: Utils.short_call_snippet("Ash.Changeset", fun_name, rest),
        details: "Only action preparation executed",
        line: opts.line,
        test_name: opts.test_name,
        test_kind: opts.test_kind,
        assertion_context: opts.assertion_context
      })
    end
  end

  defp infer_changeset_step(_, _, _, _, _), do: nil

  defp infer_module_step(module_name, node_id, fun_name, lookup, opts) do
    node = Map.get(lookup.by_id, node_id)
    short_name = List.last(String.split(node_id, "."))

    {type, kind, action} =
      cond do
        match?(%{type: "rule"}, node) and fun_name == "evaluate" ->
          {:assertion, :rule_check, "evaluate"}

        match?(%{type: "job"}, node) and fun_name == "perform" ->
          {:job, :job_execute, fun_name}

        fun_name == "handle_webhook" ->
          {:entry, :trigger_receive, fun_name}

        fun_name == "run" and match?(%{type: type} when type in ["transfer", "reactor"], node) ->
          {:entry, :action_execute, fun_name}

        true ->
          {:entry, :action_execute, fun_name}
      end

    FlowSummary.build_step(%{
      type: type,
      kind: kind,
      label: infer_module_label(type, short_name, fun_name),
      node_id: node_id,
      focus_node_id: ModuleIndex.infer_module_focus(node_id, node, fun_name, lookup),
      focus_targets: [],
      emits: [],
      reacts_to: nil,
      action: action,
      actor: nil,
      module_function: "#{module_name}.#{fun_name}",
      source_snippet:
        Map.get(opts.assertion_context || %{}, :source_snippet) ||
          Utils.short_call_snippet(module_name, fun_name, []),
      details: nil,
      line: opts.line,
      test_name: opts.test_name,
      test_kind: opts.test_kind,
      assertion_context: opts.assertion_context
    })
  end

  defp infer_ash_trace([resource_ast | rest], fun_name, call_ast, caller) do
    with resource_name when is_binary(resource_name) <-
           resolve_runtime_module_name(resource_ast, caller) do
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
    with resource_name when is_binary(resource_name) <-
           resolve_runtime_module_name(resource_ast, caller) do
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
    with module_name when is_binary(module_name) <-
           resolve_runtime_module_name(module_ast, caller) do
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
        fun_name == "evaluate" -> {:assertion, :rule_check, fun_name}
        fun_name == "handle_webhook" -> {:entry, :trigger_receive, fun_name}
        fun_name == "perform" -> {:job, :job_execute, fun_name}
        true -> {:entry, :action_execute, fun_name}
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

  defp resolve_runtime_module_name(ast, caller) do
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

  defp extract_keyword_action(keyword_ast) when is_list(keyword_ast) do
    Enum.find_value(keyword_ast, fn
      {:action, value} -> ModuleIndex.extract_action_name(value)
      _ -> nil
    end)
  end

  defp extract_keyword_action(_keyword_ast), do: nil

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

  defp build_trace_attrs(node_id, attrs) when is_binary(node_id) do
    attrs
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> Map.put(:node_id, node_id)
    |> Map.put(:capture_origin, :automatic)
  end

  defp runtime_traceable_module?(module_name, caller_file)
       when is_binary(module_name) and is_binary(caller_file) do
    with {:ok, module} <- safe_module_atom(module_name),
         true <- Code.ensure_loaded?(module),
         source when is_list(source) <- module.module_info(:compile)[:source],
         source_path <- Path.expand(List.to_string(source)),
         project_root when is_binary(project_root) <- project_root(caller_file),
         true <- String.starts_with?(source_path, project_root <> "/") do
      relative_path = String.replace_prefix(source_path, project_root <> "/", "")
      String.starts_with?(relative_path, "lib/") or String.contains?(relative_path, "/lib/")
    else
      _ -> false
    end
  end

  defp safe_module_atom(module_name) when is_binary(module_name) do
    try do
      {:ok, String.to_existing_atom("Elixir." <> module_name)}
    rescue
      ArgumentError -> :error
    end
  end

  defp project_root(caller_file) do
    caller_file
    |> Path.expand()
    |> Path.dirname()
    |> find_project_root()
  end

  defp find_project_root(dir) do
    parent = Path.dirname(dir)

    cond do
      File.exists?(Path.join(dir, "mix.exs")) ->
        dir

      parent != dir ->
        find_project_root(parent)

      true ->
        nil
    end
  end

  defp action_focus(node_id, nil), do: node_id
  defp action_focus(node_id, action), do: "#{node_id}:action:#{action}"

  defp infer_status_from_pattern({:ok, _}), do: :passed
  defp infer_status_from_pattern(:ok), do: :passed
  defp infer_status_from_pattern(true), do: :passed
  defp infer_status_from_pattern({:error, _, _}), do: :failed
  defp infer_status_from_pattern({:error, _}), do: :failed
  defp infer_status_from_pattern(_), do: :matched
end
