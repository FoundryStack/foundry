defmodule Foundry.Copilot.ContextBuilder do
  def build(opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    [tier_0_core(), tier_1_project(project_root), tier_2_status(project_root)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n---\n\n")
  end

  # Tier 0: Foundry methodology — ships with the app, never changes per-project
  defp tier_0_core do
    Application.app_dir(:foundry, "priv/prompts/core.md") |> File.read!()
  end

  # Tier 1: Project identity — AGENTS.md + stack versions from mix.exs
  defp tier_1_project(project_root) do
    agents_md = read_file(Path.join(project_root, "AGENTS.md"))
    mix_versions = extract_mix_versions(project_root)
    [agents_md, mix_versions] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  # Tier 2: Dynamic status — run mix foundry.project.status if available, else skip
  defp tier_2_status(project_root) do
    case System.cmd("mix", ["foundry.project.status", "--json"],
           cd: project_root, stderr_to_stdout: true) do
      {output, 0} -> "## Project Status\n\n```json\n#{output}\n```"
      _ -> ""
    end
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
      _ -> ""
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      _ -> ""
    end
  end
end
