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
    [agents_md, mix_versions] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  # Tier 2: Dynamic status + system architecture
  defp tier_2_status(data) do
    status = get_project_status(data)
    context_map = get_system_context(data)
    [status, context_map] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  defp get_project_status(data) do
    status = Foundry.Status.build_from_nodes(data.project_root, data.manifest, data.nodes)
    "## Project Status\n\n```json\n#{Jason.encode!(status)}\n```"
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

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      _ -> ""
    end
  end
end
