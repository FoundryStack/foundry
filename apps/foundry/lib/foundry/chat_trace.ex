defmodule Foundry.ChatTrace do
  @moduledoc """
  Normalizes structured provider events into a UI-friendly Studio copilot trace.
  """

  @max_paths 12
  @path_keys ~w(path paths file file_path filepath filename target source destination cwd repo_root root)
  @command_keys ~w(command cmd argv args input)
  @tool_keys ~w(tool tool_name name recipient_name)
  @global_context_tools ["project_status", "system_graph"]
  @governed_shell_prefixes [
    "mix foundry.project.context",
    "mix foundry.pattern.find",
    "mix foundry.exdoc",
    "rg ",
    "sed ",
    "cat ",
    "find "
  ]

  def normalize(provider, raw_event) when is_map(raw_event) do
    normalized_provider = normalize_provider(provider, raw_event)
    item = Map.get(raw_event, "item")
    type = Map.get(raw_event, "type", "unknown")
    item_type = extract_item_type(item)
    tool = extract_tool(raw_event, item)
    command = extract_command(raw_event, item)
    paths = extract_paths(raw_event) |> Enum.uniq() |> Enum.take(@max_paths)
    phase = extract_phase(raw_event, type, item_type, tool, command)
    category = classify(type, item_type, tool, command, paths, phase)
    file_access = classify_file_access(type, item_type, tool, command, paths, raw_event)

    %{
      id: System.unique_integer([:positive, :monotonic]),
      provider: normalized_provider,
      type: type,
      item_type: item_type,
      category: category,
      phase: phase,
      tool: tool,
      command: command,
      paths: paths,
      file_access: file_access,
      summary: Map.get(raw_event, "message") || Map.get(raw_event, "summary"),
      duplicate_key: duplicate_key(phase, category, tool, command, paths, type),
      title: build_title(category, phase, type, item_type, tool, command, paths, raw_event),
      detail: build_detail(type, item_type, command, paths, raw_event),
      raw: raw_event
    }
  end

  def normalize(provider, raw_event) do
    normalize(provider, %{"type" => "raw_event", "value" => inspect(raw_event)})
  end

  def summarize_run(events) when is_list(events) do
    filtered_events = Enum.reject(events, &(&1.type in ~w(thread.started)))
    grouped_events = grouped_timeline(filtered_events)

    tools =
      filtered_events
      |> Enum.map(& &1.tool)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    files =
      filtered_events
      |> Enum.flat_map(&Map.get(&1, :paths, []))
      |> Enum.uniq()

    read_files =
      filtered_events
      |> Enum.filter(&(Map.get(&1, :file_access) == :read))
      |> Enum.flat_map(&Map.get(&1, :paths, []))
      |> Enum.uniq()

    written_files =
      filtered_events
      |> Enum.filter(&(Map.get(&1, :file_access) == :write))
      |> Enum.flat_map(&Map.get(&1, :paths, []))
      |> Enum.uniq()

    %{
      event_count: length(filtered_events),
      grouped_event_count: Enum.count(grouped_events),
      grouped_events: grouped_events,
      phase_groups: group_by_phase(grouped_events),
      tools: tools,
      files: files,
      read_files: read_files,
      written_files: written_files,
      tool_count: length(tools),
      file_count: length(files),
      phase_counts: Enum.frequencies_by(filtered_events, & &1.phase),
      provenance: provenance(filtered_events)
    }
  end

  def grouped_timeline(events) when is_list(events) do
    events
    |> Enum.reverse()
    |> Enum.reduce([], fn event, acc ->
      case acc do
        [%{duplicate_key: key} = existing | rest] when key != nil and key == event.duplicate_key ->
          merged =
            existing
            |> Map.update(:count, 1, &(&1 + 1))
            |> Map.put(:detail, merged_detail(existing, event))
            |> Map.update(:paths, event.paths, &Enum.uniq(&1 ++ event.paths))

          [merged | rest]

        _ ->
          [Map.put(event, :count, 1) | acc]
      end
    end)
    |> Enum.reverse()
  end

  def phase_label(:context), do: "Context"
  def phase_label(:retrieval), do: "Retrieval"
  def phase_label(:proposal), do: "Proposal"
  def phase_label(:verification), do: "Verification"
  def phase_label(:shell_retrieval), do: "Shell Retrieval"
  def phase_label(:shell_fallback), do: "Shell Fallback"
  def phase_label(:reasoning), do: "Reasoning"
  def phase_label(:session), do: "Session"
  def phase_label(:final), do: "Final"
  def phase_label(_phase), do: "Activity"

  def pretty_raw(%{raw: raw}), do: pretty_raw(raw)

  def pretty_raw(raw) when is_map(raw) do
    Jason.encode!(raw, pretty: true)
  rescue
    _ -> inspect(raw, pretty: true, limit: :infinity)
  end

  def pretty_raw(raw), do: inspect(raw, pretty: true, limit: :infinity)

  defp normalize_provider(provider, raw_event) do
    case Map.get(raw_event, "provider") do
      "foundry" -> :foundry
      nil -> provider
      other when is_binary(other) -> String.to_atom(other)
      _ -> provider
    end
  end

  defp extract_phase(raw_event, type, item_type, tool, command) do
    case Map.get(raw_event, "phase") do
      phase when is_binary(phase) -> phase_to_atom(phase)
      phase when is_atom(phase) and not is_nil(phase) -> phase
      _ -> infer_phase(raw_event, type, item_type, tool, command)
    end
  end

  defp infer_phase(raw_event, type, item_type, tool, command) do
    provider = Map.get(raw_event, "provider")

    cond do
      provider == "foundry" and String.contains?(type, "context") -> :context
      provider == "foundry" and String.contains?(type, "proposal") -> :proposal
      provider == "foundry" and String.contains?(type, "session") -> :session
      provider == "foundry" -> :retrieval
      item_type in ["custom_tool_call", "function_call", "tool_call"] -> :retrieval
      present?(tool) -> :retrieval
      command && String.starts_with?(command, "mix test") -> :verification
      command && shell_retrieval_command?(raw_event, command) -> :shell_retrieval
      command -> :shell_fallback
      String.contains?(type, "reason") -> :reasoning
      String.contains?(type, "completed") -> :final
      true -> :retrieval
    end
  end

  defp phase_to_atom("context"), do: :context
  defp phase_to_atom("retrieval"), do: :retrieval
  defp phase_to_atom("proposal"), do: :proposal
  defp phase_to_atom("verification"), do: :verification
  defp phase_to_atom("shell_retrieval"), do: :shell_retrieval
  defp phase_to_atom("shell_fallback"), do: :shell_fallback
  defp phase_to_atom("reasoning"), do: :reasoning
  defp phase_to_atom("session"), do: :session
  defp phase_to_atom("final"), do: :final
  defp phase_to_atom(_), do: :retrieval

  defp extract_item_type(%{"type" => item_type}) when is_binary(item_type), do: item_type
  defp extract_item_type(_item), do: nil

  defp extract_tool(raw_event, item) do
    find_first_string(item, @tool_keys) || find_first_string(raw_event, @tool_keys)
  end

  defp extract_command(raw_event, item) do
    extract_command_value(find_first(item, @command_keys)) ||
      extract_command_value(find_first(raw_event, @command_keys))
  end

  defp extract_command_value(value) when is_binary(value), do: String.trim(value)

  defp extract_command_value(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  defp extract_command_value(_value), do: nil

  defp extract_paths(value) when is_map(value) do
    Enum.flat_map(value, fn {key, nested} ->
      if key in @path_keys do
        normalize_paths(nested)
      else
        extract_paths(nested)
      end
    end)
  end

  defp extract_paths(value) when is_list(value), do: Enum.flat_map(value, &extract_paths/1)
  defp extract_paths(_value), do: []

  defp normalize_paths(value) when is_binary(value), do: [value]
  defp normalize_paths(value) when is_list(value), do: Enum.flat_map(value, &normalize_paths/1)
  defp normalize_paths(value) when is_map(value), do: extract_paths(value)
  defp normalize_paths(_value), do: []

  defp classify(type, item_type, tool, command, paths, phase) do
    cond do
      String.contains?(type, "error") -> :error
      phase == :proposal -> :proposal
      phase == :context -> :context
      phase == :session -> :session
      item_type in ["custom_tool_call", "function_call", "tool_call"] -> :tool
      is_binary(tool) and tool != "" -> :tool
      is_binary(command) and command != "" -> :command
      paths != [] -> :file
      String.contains?(type, "reason") -> :reasoning
      String.contains?(type, "agent_message") -> :message
      String.contains?(type, "completed") -> :result
      true -> :other
    end
  end

  defp classify_file_access(_type, _item_type, _tool, _command, [], _raw_event), do: nil

  defp classify_file_access(type, item_type, tool, command, _paths, raw_event) do
    lowered_type = String.downcase(type || "")
    lowered_tool = String.downcase(tool || "")
    lowered_command = String.downcase(command || "")
    lowered_message = String.downcase(Map.get(raw_event, "message", ""))

    cond do
      String.contains?(lowered_type, ["write", "edit", "patch", "create", "save"]) ->
        :write

      String.contains?(lowered_tool, ["apply_patch", "write", "edit", "create"]) ->
        :write

      String.contains?(lowered_command, ["apply_patch", "mv ", "cp ", "touch ", "mkdir ", "tee "]) ->
        :write

      String.contains?(lowered_command, [">", ">>"]) ->
        :write

      String.contains?(lowered_message, ["wrote", "edited", "updated", "created"]) ->
        :write

      item_type in ["custom_tool_call", "function_call", "tool_call"] and present?(command) ->
        :read

      present?(command) ->
        :read

      true ->
        :read
    end
  end

  defp build_title(:context, _phase, _type, _item_type, _tool, _command, _paths, raw_event) do
    case Map.get(raw_event, "cache") do
      "miss" -> "Context cache miss — rebuilding"
      "hit" -> "Loaded context (cached)"
      _ -> Map.get(raw_event, "message", "Loaded Foundry context")
    end
  end

  defp build_title(:session, _phase, _type, _item_type, _tool, _command, _paths, raw_event) do
    Map.get(raw_event, "message", "Updated session memory")
  end

  defp build_title(:proposal, _phase, _type, _item_type, _tool, _command, _paths, raw_event) do
    Map.get(raw_event, "message", "Proposal flow event")
  end

  defp build_title(:tool, _phase, _type, item_type, tool, _command, paths, raw_event) do
    cond do
      tool == "module_context" and paths != [] ->
        "Read module #{List.first(paths)}"

      tool == "module_context" ->
        case Map.get(raw_event, "path") || Map.get(raw_event, "message") do
          nil -> "Read module context"
          path when is_binary(path) -> "Read module #{path}"
        end

      tool == "read_doc" and paths != [] ->
        "Read document #{Path.basename(List.first(paths))}"

      tool == "read_doc" ->
        case Map.get(raw_event, "path") do
          nil -> "Read document"
          path -> "Read document #{Path.basename(path)}"
        end

      tool in ["apply_patch", "write_file", "create_file"] and paths != [] ->
        "Write #{path_tail_str(List.first(paths))}"

      tool in ["read_file", "cat", "open"] and paths != [] ->
        "Read #{path_tail_str(List.first(paths))}"

      present?(tool) -> "Tool: #{tool}"
      present?(item_type) -> "Completed #{item_type}"
      true -> "Tool activity"
    end
  end

  defp build_title(:command, _phase, _type, _item_type, _tool, command, _paths, _raw_event) do
    inner = unwrap_shell_command(command)
    "Shell: #{truncate(inner, 100)}"
  end

  defp build_title(:file, _phase, _type, _item_type, _tool, _command, [path], _raw_event) do
    "Referenced file #{Path.basename(path)}"
  end

  defp build_title(:file, _phase, _type, _item_type, _tool, _command, paths, _raw_event) do
    "Referenced #{length(paths)} files"
  end

  defp build_title(:reasoning, _phase, type, _item_type, _tool, _command, _paths, _raw_event) do
    "Reasoning event #{type}"
  end

  defp build_title(:message, _phase, _type, _item_type, _tool, _command, _paths, _raw_event) do
    "Assistant message update"
  end

  defp build_title(:result, _phase, type, _item_type, _tool, _command, _paths, _raw_event) do
    "Completed event #{type}"
  end

  defp build_title(:error, _phase, type, _item_type, _tool, _command, _paths, _raw_event) do
    "Provider error #{type}"
  end

  defp build_title(:other, phase, type, item_type, _tool, _command, _paths, _raw_event) do
    label =
      [Atom.to_string(phase), type, item_type]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" / ")

    if label == "", do: "Provider event", else: label
  end

  defp build_detail(type, item_type, command, paths, raw_event) do
    output =
      Map.get(raw_event, "output") ||
        Map.get(raw_event, "result") ||
        Map.get(raw_event, "content") ||
        Map.get(raw_event, "data")

    parts =
      [
        if(present?(command), do: unwrap_shell_command(command)),
        if(present?(output) and is_binary(output), do: truncate(output, 1200)),
        if(present?(Map.get(raw_event, "message")) and not present?(command) and is_nil(output),
          do: Map.get(raw_event, "message")
        ),
        if(paths == [] and present?(item_type), do: item_type)
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> if type != "unknown", do: type, else: nil
      _ -> Enum.join(parts, "\n")
    end
  end

  defp duplicate_key(phase, category, tool, command, paths, _type) do
    {
      phase,
      category,
      tool,
      normalize_duplicate_command(command),
      Enum.sort(paths)
    }
  end

  defp normalize_duplicate_command(nil), do: nil

  defp normalize_duplicate_command(command) do
    String.replace(command, ~r/\s+/, " ")
  end

  defp merged_detail(existing, event) do
    base_detail = Map.get(existing, :detail)
    incoming_detail = Map.get(event, :detail)

    combined =
      case {base_detail, incoming_detail} do
        {nil, nil} -> nil
        {nil, inc} -> inc
        {base, nil} -> base
        {base, inc} when base == inc -> base
        {base, inc} -> "#{base}\n---\n#{inc}"
      end

    if existing.count > 1 do
      repeat_note = "repeated #{existing.count + 1}x"
      if combined, do: "#{combined}\n#{repeat_note}", else: repeat_note
    else
      combined
    end
  end

  defp group_by_phase(grouped_events) do
    grouped_events
    |> Enum.group_by(& &1.phase)
    |> Enum.map(fn {phase, phase_events} ->
      %{
        phase: phase,
        label: phase_label(phase),
        events: phase_events,
        count: length(phase_events)
      }
    end)
    |> Enum.sort_by(&phase_sort_order(&1.phase))
  end

  defp provenance(events) do
    %{
      cached_context_used: Enum.any?(events, &(&1.phase == :context)),
      context_refreshed:
        Enum.any?(events, fn
          %{raw: %{"cache" => "miss"}} -> true
          _ -> false
        end),
      foundry_tools_used:
        Enum.any?(events, fn
          %{provider: :foundry, category: category}
          when category in [:tool, :context, :proposal] ->
            true

          _ ->
            false
        end),
      shell_retrieval_used: Enum.any?(events, &(&1.phase == :shell_retrieval)),
      true_fallback_used: Enum.any?(events, &(&1.phase == :shell_fallback)),
      redundant_global_context_fetches: redundant_global_context_fetches(events),
      shell_fallback_used: Enum.any?(events, &(&1.phase == :shell_fallback)),
      proposal_flow_used: Enum.any?(events, &(&1.phase == :proposal))
    }
  end

  defp phase_sort_order(:context), do: 0
  defp phase_sort_order(:session), do: 1
  defp phase_sort_order(:retrieval), do: 2
  defp phase_sort_order(:shell_retrieval), do: 3
  defp phase_sort_order(:reasoning), do: 4
  defp phase_sort_order(:proposal), do: 5
  defp phase_sort_order(:shell_fallback), do: 6
  defp phase_sort_order(:verification), do: 7
  defp phase_sort_order(:final), do: 8
  defp phase_sort_order(_), do: 9

  defp find_first(map, keys) when is_map(map), do: Enum.find_value(keys, &Map.get(map, &1))
  defp find_first(_map, _keys), do: nil

  defp find_first_string(map, keys) do
    case find_first(map, keys) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp shell_retrieval_command?(raw_event, command) do
    normalized = normalize_duplicate_command(command)

    not explicit_fallback?(raw_event) and
      Enum.any?(@governed_shell_prefixes, &String.contains?(normalized, &1))
  end

  defp explicit_fallback?(raw_event) do
    text =
      [Map.get(raw_event, "message"), Map.get(raw_event, "summary"), Map.get(raw_event, "type")]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(text, "fallback")
  end

  defp redundant_global_context_fetches(events) do
    events
    |> Enum.count(fn
      %{tool: tool, provider: provider}
      when tool in @global_context_tools and provider != :foundry ->
        true

      %{tool: tool} when tool in @global_context_tools ->
        true

      _ ->
        false
    end)
  end

  defp truncate(nil, _limit), do: nil

  defp truncate(value, limit) do
    if String.length(value) > limit do
      String.slice(value, 0, limit - 1) <> "..."
    else
      value
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp unwrap_shell_command(nil), do: nil

  defp unwrap_shell_command(command) do
    cond do
      # /bin/zsh -lc "..." or /bin/bash -c "..."
      match = Regex.run(~r{/bin/\w+\s+-\w+\s+"(.+)"$}s, command) ->
        String.trim(Enum.at(match, 1))

      # /bin/sh -c '...' or /bin/bash -c '...'
      match = Regex.run(~r{/bin/(?:ba)?sh\s+-\w+\s+'(.+)'$}s, command) ->
        String.trim(Enum.at(match, 1))

      true ->
        command
    end
  end

  defp path_tail_str(path) when is_binary(path) do
    path |> String.split("/") |> Enum.take(-2) |> Enum.join("/")
  end

  defp path_tail_str(path), do: to_string(path)
end
