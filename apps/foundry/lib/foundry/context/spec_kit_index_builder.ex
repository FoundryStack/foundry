defmodule Foundry.Context.SpecKitIndexBuilder do
  @moduledoc """
  Builds the spec-kit index by scanning ADRs, runbooks, regulations, and other
  documentation files. Extracts summaries, tags, and token counts.

  Token estimation uses a conservative approximation: byte_size / 3.
  English prose + Elixir identifiers average ~3.5 chars/token; dividing by 3
  slightly overestimates (correct for warning thresholds).
  """

  @excluded_files ~w[
    docs/project_context_schema.md
    docs/spec_kit_index_schema.md
    docs/mix_task_summary_schemas.md
    docs/reference-project-fixture.md
    docs/manifest-schema-draft.md
  ]

  @stop_words ~w[the a an is are for with by in on at to of and or not this that
                 it its be as from will must when if all any each per no]

  @spec build(String.t()) :: map()
  def build(project_root) do
    adrs = scan_dir(project_root, "docs/adrs/", "adr")
    runbooks = scan_dir(project_root, "docs/runbooks/", "runbook")
    regs = scan_dir(project_root, "docs/regulations/", "regulation")
    agents = scan_exact(project_root, "AGENTS.md", "agents", "AGENTS")
    rules = scan_dir(project_root, ".foundry/usage_rules/", "usage_rules")

    all_entries = adrs ++ runbooks ++ regs ++ List.wrap(agents) ++ rules
    token_count = estimate_tokens(all_entries)

    %{
      "index_token_count" => token_count,
      "index_token_warn" => token_count > 360,
      "index_token_limit" => 400,
      "adrs" => adrs,
      "runbooks" => runbooks,
      "regulations" => regs,
      "agents" => agents,
      "usage_rules" => rules
    }
  end

  # ---------------------------------------------------------------------------
  # Directory scanning
  # ---------------------------------------------------------------------------

  defp scan_dir(project_root, dir_path, doc_type) do
    full_path = Path.join(project_root, dir_path)

    case File.ls(full_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&Path.join(dir_path, &1))
        |> Enum.reject(&(&1 in @excluded_files))
        |> Enum.map(&extract_document(project_root, &1, doc_type))
        |> Enum.filter(&(&1 != nil))

      {:error, _} ->
        []
    end
  end

  defp scan_exact(project_root, file_path, doc_type, title) do
    full_path = Path.join(project_root, file_path)

    case File.read(full_path) do
      {:ok, content} ->
        [extract_document_from_content(file_path, content, doc_type, title)]

      {:error, _} ->
        nil
    end
    |> List.wrap()
    |> Enum.filter(&(&1 != nil))
  end

  # ---------------------------------------------------------------------------
  # Document extraction
  # ---------------------------------------------------------------------------

  defp extract_document(project_root, path, doc_type) do
    case File.read(Path.join(project_root, path)) do
      {:ok, content} ->
        # Extract title from filename (e.g., "ADR-001-stack-selection.md" → "ADR-001")
        title =
          path
          |> Path.basename(".md")
          |> String.slice(0, String.length(Path.basename(path)) - 3)

        extract_document_from_content(path, content, doc_type, title)

      {:error, _} ->
        nil
    end
  end

  defp extract_document_from_content(path, content, doc_type, title) do
    summary = extract_summary(content)
    tags = extract_tags(content)

    %{
      path: path,
      title: title,
      type: doc_type,
      summary: summary,
      tags: tags
    }
  end

  # ---------------------------------------------------------------------------
  # Summary and tag extraction
  # ---------------------------------------------------------------------------

  defp extract_summary(content) do
    content
    |> String.split("\n\n")
    |> Enum.reject(&skip_paragraph?/1)
    |> List.first()
    |> truncate_summary()
  end

  defp skip_paragraph?(text) do
    trimmed = String.trim(text)
    trimmed == "" or
      String.starts_with?(trimmed, "#") or
      String.starts_with?(trimmed, "```") or
      String.starts_with?(trimmed, ">") or
      String.starts_with?(trimmed, "---") or
      String.starts_with?(trimmed, "**")
  end

  defp truncate_summary(nil), do: nil

  defp truncate_summary(text) do
    result =
      text
      |> String.split(~r/(?<=[.!?])\s+/, parts: 3)
      |> Enum.take(2)
      |> Enum.join(" ")

    if String.length(result) > 300 do
      String.slice(result, 0, 297) <> "..."
    else
      result
    end
  end

  defp extract_tags(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in @stop_words))
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.take(12)
  end

  # ---------------------------------------------------------------------------
  # Token counting
  # ---------------------------------------------------------------------------

  defp estimate_tokens(entries) do
    entries |> Jason.encode!() |> byte_size() |> div(3)
  end
end
