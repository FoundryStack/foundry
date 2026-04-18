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
    "provider" => "pvr"
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
    "calls_provider" => "cp"
  }

  def format(%{"nodes" => nodes, "edges" => edges} = context) do
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
        [] -> []
        rels -> ["rels: #{rels |> Enum.map(&format_relationship(&1, reverse)) |> Enum.join(", ")}"]
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
      |> then(&(if node["data_layer"], do: &1 ++ ["dl=#{short_data_layer(node["data_layer"])}"], else: &1))
      |> then(&(if node["paper_trail"], do: &1 ++ ["paper_trail"], else: &1))
      |> then(&(if node["archival"], do: &1 ++ ["archival"], else: &1))
      |> then(&(if node["pending_migrations"], do: &1 ++ ["pending!"], else: &1))
      |> then(&(if node["authentication_subject"], do: &1 ++ ["auth_subject"], else: &1))
      |> then(&(if node["rate_limited"], do: &1 ++ ["rate_limited"], else: &1))
      |> then(fn flags ->
        if flags == [], do: [], else: [Enum.join(flags, " · ")]
      end)

    initial_lines ++
      attr_section ++
      action_section ++
      rel_section ++
      comp_section ++
      adr_section ++
      flag_section
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
    type = case rel["type"] do
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
    adr_section = format_adr_section(spec_kit["adrs"])
    rb_section = format_rb_section(spec_kit["runbooks"])
    reg_section = format_reg_section(spec_kit["regulations"])

    parts = [adr_section, rb_section, reg_section] |> Enum.reject(&(&1 == ""))

    if parts == [], do: "", else: "## Spec-Kit\n\n" <> Enum.join(parts, "\n\n")
  end

  defp format_adr_section(nil), do: ""

  defp format_adr_section(adrs) when adrs == [], do: ""

  defp format_adr_section(adrs) do
    adr_lines =
      adrs
      |> Enum.map(fn a ->
        tags = (a["tags"] || []) |> Enum.take(5) |> Enum.join(", ")
        tags_str = if tags != "", do: " [#{tags}]", else: ""
        "  #{a["id"] || a["filename"]}: #{a["title"]}#{tags_str}"
      end)

    "### ADRs\n\n" <> Enum.join(adr_lines, "\n")
  end

  defp format_rb_section(nil), do: ""

  defp format_rb_section(runbooks) when runbooks == [], do: ""

  defp format_rb_section(runbooks) do
    rb_lines =
      runbooks
      |> Enum.map(fn r -> "  #{r["filename"]}: #{r["title"]}" end)

    "### Runbooks\n\n" <> Enum.join(rb_lines, "\n")
  end

  defp format_reg_section(nil), do: ""

  defp format_reg_section(regs) when regs == [], do: ""

  defp format_reg_section(regs) do
    reg_lines =
      regs
      |> Enum.map(fn r -> "  #{r["id"] || r["filename"]}: #{r["title"]}" end)

    "### Regulations\n\n" <> Enum.join(reg_lines, "\n")
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
