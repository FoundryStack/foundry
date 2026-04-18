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

  # Tier 2: Dynamic status + system architecture
  # Runs mix foundry.project.status (health) and mix foundry.project.context (full system map)
  defp tier_2_status(project_root) do
    status = get_project_status(project_root)
    context_map = get_system_context(project_root)
    [status, context_map] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  defp get_project_status(project_root) do
    case System.cmd("mix", ["foundry.project.status", "--json"],
           cd: project_root, stderr_to_stdout: false) do
      {output, 0} -> "## Project Status\n\n```json\n#{output}\n```"
      _ -> ""
    end
  end

  defp get_system_context(project_root) do
    case System.cmd("mix", ["foundry.project.context"],
           cd: project_root, stderr_to_stdout: false) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, context} ->
            formatted = Foundry.Context.LLMFormatter.format(context)
            "## System Architecture (Full Project Context)\n\n#{formatted}"
          {:error, decode_error} ->
            IO.warn("⚠️  System Architecture decode error: #{inspect(decode_error)}")
            ""
        end
      {_output, exit_code} ->
        IO.warn("⚠️  System Architecture context failed (exit #{exit_code})")
        ""
    end
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
