defmodule Foundry.Context.LLMFormatter do
  @moduledoc """
  Formats project context for LLM consumption using compact text notation.

  Achieves ~60-70% token reduction vs raw JSON by:
  - Module dictionary encoding (short aliases for module names)
  - Compact attribute notation (name:type[:flag,...])
  - Compact edge notation (A1 --rel--> B1)
  - Type abbreviation legend
  """

  @type_abbr %{
    "resource" => "res",
    "reactor" => "rxr",
    "transfer" => "txr",
    "oban_job" => "job",
    "ash_authentication" => "auth",
    "ash_policy" => "pol",
    "blueprint" => "bp",
    "adapter" => "adp"
  }

  @attr_type_abbr %{
    "string" => "str",
    "integer" => "int",
    "boolean" => "bool",
    "decimal" => "dec",
    "float" => "float",
    "datetime" => "dt",
    "date" => "date",
    "map" => "map",
    "uuid" => "uuid"
  }

  @edge_abbr %{
    "references" => "ref",
    "referenced_by" => "rb",
    "writes" => "w",
    "reads" => "r",
    "async" => "async",
    "guards" => "grd",
    "sequence" => "seq",
    "compensation" => "comp",
    "configures" => "cfg",
    "authenticates" => "ath",
    "persists_to" => "pers",
    "queues_via" => "que",
    "calls_adapter" => "ca"
  }

  @doc_title_limit 90
  @doc_summary_limit 170

  def format(context) do
    # Ensure all keys are strings for consistent processing,
    # as context can come from internal assembly (atoms) or JSON decode (strings).
    context = stringify_keys(context)
    nodes = context["nodes"] || []
    edges = context["edges"] || []

    aliases = build_aliases(nodes)
    reverse = Map.new(aliases, fn {k, v} -> {v, k} end)

    [
      format_header(context),
      format_legend(),
      format_aliases(aliases),
      format_nodes(nodes, reverse),
      format_edges(edges, reverse),
      format_spec_kit(context["spec_kit"])
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(v) when is_atom(v) and v not in [true, false, nil], do: Atom.to_string(v)
  defp stringify_keys(v), do: v

  defp format_header(context) do
    project = context["project"] || ""
    project_type = context["project_type"] || "standard"
    domain_type = context["domain_type"]
    dt_part = if domain_type, do: " · #{domain_type}", else: ""

    "# System Map: #{project} (#{project_type}#{dt_part})\n\nCompact text format for LLM consumption."
  end

  defp format_legend do
    types = Enum.map_join(@type_abbr, "  ", fn {k, v} -> "#{v}=#{k}" end)
    edges = Enum.map_join(@edge_abbr, "  ", fn {k, v} -> "#{v}=#{k}" end)

    """
    ## Legend

    **Types:** #{types}
    **Attrs:** pk=primary_key  pii=pii  s=sensitive  m=money  u=unique  req=required
    **Edges:** #{edges}
    """
  end

  defp format_aliases(aliases) do
    lines =
      aliases
      |> Enum.sort_by(fn {_a, name} -> name end)
      |> Enum.chunk_every(5)
      |> Enum.map(fn chunk ->
        Enum.map_join(chunk, "  ", fn {a, name} -> "#{a}=#{name}" end)
      end)

    "## Module Aliases\n\n" <> Enum.join(lines, "\n")
  end

  defp format_nodes(nodes, reverse) do
    body = nodes |> Enum.map(&format_node(&1, reverse)) |> Enum.join("\n\n")
    "## Nodes\n\n" <> body
  end

  defp format_node(node, reverse) do
    alias_name = Map.get(reverse, node["module"], node["module"])
    type = Map.get(@type_abbr, node["type"], node["type"] || "?")
    domain = node["domain"] || ""
    sensitive = if node["sensitive"], do: " · **sensitive**", else: ""
    desc = node["description"] || ""
    desc_text = if desc != "", do: "> #{String.slice(desc, 0, 120)}", else: ""

    initial_lines = [
      "[#{alias_name}] #{type} · #{short_domain(domain)}#{sensitive}",
      desc_text
    ]

    # Build all sections and combine
    attr_section =
      case node["attributes"] || [] do
        [] -> []
        attrs -> ["attrs: #{attrs |> Enum.map(&format_attr/1) |> Enum.join(", ")}"]
      end

    action_section =
      case node["actions"] || [] do
        [] -> []
        actions -> ["actions: #{actions |> Enum.map(& &1["name"]) |> Enum.join(", ")}"]
      end

    rel_section =
      case node["relationships"] || [] do
        [] ->
          []

        rels ->
          ["rels: #{rels |> Enum.map(&format_relationship(&1, reverse)) |> Enum.join(", ")}"]
      end

    comp_section =
      case node["compliance"] || [] do
        [] -> []
        compliance -> ["compliance: #{Enum.join(compliance, ", ")}"]
      end

    adr_section =
      case node["adrs"] || [] do
        [] -> []
        adrs -> ["adrs: #{Enum.join(adrs, ", ")}"]
      end

    flag_section =
      []
      |> then(
        &if node["data_layer"], do: &1 ++ ["dl=#{short_data_layer(node["data_layer"])}"], else: &1
      )
      |> then(&if node["paper_trail"], do: &1 ++ ["paper_trail"], else: &1)
      |> then(&if node["archival"], do: &1 ++ ["archival"], else: &1)
      |> then(&if node["pending_migrations"], do: &1 ++ ["pending!"], else: &1)
      |> then(&if node["authentication_subject"], do: &1 ++ ["auth_subject"], else: &1)
      |> then(&if node["rate_limited"], do: &1 ++ ["rate_limited"], else: &1)
      |> then(fn flags ->
        if flags == [], do: [], else: [Enum.join(flags, " · ")]
      end)

    (initial_lines ++
       attr_section ++
       action_section ++
       rel_section ++
       comp_section ++
       adr_section ++
       flag_section)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n  ")
  end

  defp format_attr(attr) do
    name = attr["name"] || "?"
    type_name = attr["type"] || "?"
    type = type_name |> String.split(".") |> List.last() |> abbreviate_type()

    flags = []
    flags = if attr["primary_key"], do: flags ++ ["pk"], else: flags
    flags = if attr["pii"], do: flags ++ ["pii"], else: flags
    flags = if attr["sensitive"], do: flags ++ ["s"], else: flags
    flags = if attr["money"], do: flags ++ ["m"], else: flags

    if flags == [] do
      "#{name}:#{type}"
    else
      "#{name}:#{type}:#{Enum.join(flags, ":")}"
    end
  end

  defp abbreviate_type(type_name) do
    type_name
    |> String.downcase()
    |> then(fn t ->
      case @attr_type_abbr[t] do
        nil -> t
        abbr -> abbr
      end
    end)
  end

  defp format_relationship(rel, reverse) do
    type =
      case rel["type"] do
        "has_many" -> "has_many"
        "belongs_to" -> "belongs_to"
        "has_one" -> "has_one"
        "many_to_many" -> "m2m"
        t -> t
      end

    target = Map.get(reverse, rel["related_resource"], rel["related_resource"])

    if rel["source_attribute"] do
      "#{type}:#{target}(#{rel["source_attribute"]})"
    else
      "#{type}:#{target}"
    end
  end

  defp format_edges(edges, reverse) do
    body = edges |> Enum.map(&format_edge(&1, reverse)) |> Enum.join("\n")
    "## Edges\n\n" <> body
  end

  defp format_edge(edge, reverse) do
    from = Map.get(reverse, edge["from"], edge["from"])
    to = Map.get(reverse, edge["to"], edge["to"])
    rel = Map.get(@edge_abbr, edge["relation"], edge["relation"])

    extras = []
    extras = if edge["step_index"], do: extras ++ ["seq=#{edge["step_index"]}"], else: extras
    extras = if edge["step_name"], do: extras ++ ["step=#{edge["step_name"]}"], else: extras
    extras = if edge["action_name"], do: extras ++ ["act=#{edge["action_name"]}"], else: extras

    extra_str = if extras == [], do: "", else: " [#{Enum.join(extras, ",")}]"
    "#{from} --#{rel}--> #{to}#{extra_str}"
  end

  defp format_spec_kit(nil), do: ""

  defp format_spec_kit(spec_kit) do
    overview = format_spec_kit_overview(spec_kit)

    sections =
      [
        format_doc_section("AGENTS", spec_kit["agents"]),
        format_doc_section("ADRs", spec_kit["adrs"]),
        format_doc_section("Runbooks", spec_kit["runbooks"]),
        format_doc_section("Regulations", spec_kit["regulations"]),
        format_doc_section("Usage Rules", spec_kit["usage_rules"])
      ]
      |> Enum.reject(&(&1 == ""))

    parts = [overview | sections] |> Enum.reject(&(&1 == ""))

    if parts == [], do: "", else: "## Spec-Kit\n\n" <> Enum.join(parts, "\n\n")
  end

  defp format_spec_kit_overview(spec_kit) do
    counts =
      [
        {"AGENTS", count_docs(spec_kit["agents"])},
        {"ADRs", count_docs(spec_kit["adrs"])},
        {"Runbooks", count_docs(spec_kit["runbooks"])},
        {"Regulations", count_docs(spec_kit["regulations"])},
        {"Usage Rules", count_docs(spec_kit["usage_rules"])}
      ]
      |> Enum.filter(fn {_label, count} -> count > 0 end)
      |> Enum.map_join("  ", fn {label, count} -> "#{label}=#{count}" end)

    tags =
      spec_kit
      |> collect_tags()
      |> Enum.take(8)
      |> Enum.join(", ")

    token_count = spec_kit["index_token_count"] || 0
    token_warn = spec_kit["index_token_warn"] || false
    tag_line = if tags == "", do: "", else: "\nThemes: #{tags}"

    """
    ### Overview

    Counts: #{counts}
    Navigation: Prefer direct node links (`adrs`, `compliance`, `runbook`) before tag-based lookup.
    Token estimate: #{token_count} (warn: #{token_warn})#{tag_line}
    """
    |> String.trim()
  end

  defp format_doc_section(_title, nil), do: ""
  defp format_doc_section(_title, []), do: ""

  defp format_doc_section(title, docs) do
    entries =
      docs
      |> Enum.map(&format_doc_entry/1)
      |> Enum.join("\n")

    "### #{title}\n\n" <> entries
  end

  defp format_doc_entry(doc) do
    id = doc["id"] || doc["filename"] || doc["path"] || doc["title"] || "unknown"
    title = doc["title"] |> presence_or_nil() |> truncate(@doc_title_limit)
    status = doc["status"] |> presence_or_nil() |> normalize_status()
    summary = summarize_doc(doc)

    label_parts =
      [id, status, title]
      |> Enum.reject(&is_nil/1)

    case summary do
      nil -> "- " <> Enum.join(label_parts, " · ")
      text -> "- " <> Enum.join(label_parts, " · ") <> " :: " <> text
    end
  end

  defp summarize_doc(doc) do
    doc["summary"]
    |> presence_or_nil()
    |> truncate(@doc_summary_limit)
    |> case do
      nil ->
        doc["tags"]
        |> List.wrap()
        |> Enum.take(5)
        |> Enum.join(", ")
        |> presence_or_nil()

      summary ->
        summary
    end
  end

  defp normalize_status(nil), do: nil

  defp normalize_status(status) do
    status |> String.trim() |> String.downcase()
  end

  defp count_docs(nil), do: 0
  defp count_docs(docs), do: length(List.wrap(docs))

  defp collect_tags(spec_kit) do
    ["adrs", "runbooks", "regulations", "usage_rules"]
    |> Enum.flat_map(fn key ->
      spec_kit
      |> Map.get(key, [])
      |> List.wrap()
      |> Enum.flat_map(&List.wrap(&1["tags"]))
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {tag, count} -> {-count, tag} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp presence_or_nil(nil), do: nil

  defp presence_or_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      value -> value
    end
  end

  defp truncate(nil, _limit), do: nil

  defp truncate(text, limit) when is_binary(text) do
    if String.length(text) > limit do
      String.slice(text, 0, limit - 3) <> "..."
    else
      text
    end
  end

  defp build_aliases(nodes) do
    nodes
    |> Enum.sort_by(& &1["module"])
    |> Enum.group_by(fn node ->
      parts = String.split(node["module"], ".")

      case parts do
        [_, domain | _] -> domain
        [_] -> "Root"
        _ -> "Other"
      end
    end)
    |> Enum.flat_map(fn {domain, group} ->
      prefix = domain |> String.slice(0, 2) |> String.upcase()

      group
      |> Enum.with_index(1)
      |> Enum.map(fn {node, idx} -> {"#{prefix}#{idx}", node["module"]} end)
    end)
    |> Map.new()
  end

  defp short_domain(domain) do
    domain |> String.split(".") |> List.last() |> String.downcase()
  end

  defp short_data_layer(dl) do
    case dl do
      "Elixir.AshPostgres.DataLayer" -> "postgres"
      "Ash.DataLayer.Ets" -> "ets"
      "Ash.DataLayer.Mnesia" -> "mnesia"
      _ -> dl
    end
  end
end
