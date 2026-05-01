defmodule Foundry.Copilot.ContextBuilder do
  def build(opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    {:ok, manifest} = Foundry.Manifest.Parser.read(project_root)
    {nodes, edges} = Foundry.Context.GraphBuilder.build(project_root, manifest)
    spec_kit = Foundry.Context.SpecKitIndexBuilder.build(project_root)

    data = %{
      project_root: project_root,
      manifest: manifest,
      nodes: nodes,
      edges: edges,
      spec_kit: spec_kit
    }

    [tier_0_core(), tier_1_project(data), tier_2_status(data)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n---\n\n")
  end

  # Tier 0: Foundry methodology — ships with the app, never changes per-project
  defp tier_0_core do
    Application.app_dir(:foundry, "priv/prompts/core.md") |> File.read!()
  end

  # Tier 1: Project identity — AGENTS.md + stack versions from mix.exs
  defp tier_1_project(data) do
    agents_md = read_file(Path.join(data.project_root, "AGENTS.md"))
    mix_versions = extract_mix_versions(data.project_root)
    spec_kit_index = format_spec_kit_index(data.spec_kit)

    [agents_md, mix_versions, spec_kit_index]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # Tier 2: Dynamic status + LLM-optimized full project map for the orchestrator.
  defp tier_2_status(data) do
    status = get_project_status(data)
    context_map = get_system_context(data)
    [status, context_map] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  defp get_project_status(data) do
    status = Foundry.Status.build_from_nodes(data.project_root, data.manifest, data.nodes)
    "## Project Status\n\n```json\n#{Jason.encode!(status_prompt_view(status))}\n```"
  end

  defp get_system_context(data) do
    context =
      Foundry.Context.ProjectMap.assemble(data.manifest, data.nodes, data.edges, data.spec_kit)

    formatted = Foundry.Context.LLMFormatter.format(context)
    "## System Architecture (Full Project Context)\n\n#{formatted}"
  rescue
    e ->
      IO.warn("⚠️  System Architecture context error: #{inspect(e)}")
      ""
  end

  defp extract_mix_versions(project_root) do
    mix_path = Path.join(project_root, "mix.exs")

    case File.read(mix_path) do
      {:ok, contents} ->
        # Regex to find deps list in Elixir
        case Regex.run(~r/defp deps\s*(?:do|\(.*\)\s*do)\s*(.*?)\n\s*end/s, contents) do
          [_, deps] -> "## Dependency Versions\n\n```elixir\n#{deps}\n```"
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp format_spec_kit_index(nil), do: ""

  defp format_spec_kit_index(spec_kit) do
    sections =
      [
        format_doc_group("AGENTS", spec_kit["agents"] || spec_kit[:agents]),
        format_doc_group("ADRs", spec_kit["adrs"] || spec_kit[:adrs]),
        format_doc_group("Runbooks", spec_kit["runbooks"] || spec_kit[:runbooks]),
        format_doc_group("Regulations", spec_kit["regulations"] || spec_kit[:regulations]),
        format_doc_group("Usage Rules", spec_kit["usage_rules"] || spec_kit[:usage_rules])
      ]
      |> Enum.reject(&(&1 == ""))

    if sections == [] do
      ""
    else
      token_count = spec_kit["index_token_count"] || spec_kit[:index_token_count] || 0
      token_warn = spec_kit["index_token_warn"] || spec_kit[:index_token_warn] || false

      """
      ## Spec-Kit Index

      Token estimate: #{token_count} (warn: #{token_warn})

      #{Enum.join(sections, "\n\n")}
      """
      |> String.trim()
    end
  end

  defp format_doc_group(_title, nil), do: ""
  defp format_doc_group(_title, []), do: ""

  defp format_doc_group(title, docs) do
    lines =
      docs
      |> List.wrap()
      |> Enum.map(fn doc ->
        path = doc[:path] || doc["path"]
        doc_title = doc[:title] || doc["title"]
        summary = doc[:summary] || doc["summary"]
        tags = doc[:tags] || doc["tags"] || []

        suffix =
          cond do
            is_binary(summary) and summary != "" -> " - #{summary}"
            tags != [] -> " [#{Enum.take(tags, 6) |> Enum.join(", ")}]"
            true -> ""
          end

        "- #{path}: #{doc_title}#{suffix}"
      end)

    "### #{title}\n" <> Enum.join(lines, "\n")
  end

  defp status_prompt_view(status) do
    compliance = status["compliance"] || %{}
    requirements = compliance["requirements"] || []

    %{
      "generated_at" => status["generated_at"],
      "compiled_at" => status["compiled_at"],
      "project" => status["project"],
      "project_type" => status["project_type"],
      "domain_type" => status["domain_type"],
      "domains" => status["domains"],
      "sensitive_modules" => status["sensitive_modules"],
      "lint" => status["lint"],
      "migrations" => status["migrations"],
      "proposals" => status["proposals"],
      "compliance" => %{
        "total_requirements" => compliance["total_requirements"],
        "covered_count" => compliance["covered_count"],
        "planned_count" => compliance["planned_count"],
        "sample_requirements" => Enum.take(requirements, 5),
        "truncated_count" => max(length(requirements) - 5, 0)
      },
      "ci" => status["ci"],
      "stack" => status["stack"],
      "manifest" => status["manifest"]
    }
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      _ -> ""
    end
  end
end
