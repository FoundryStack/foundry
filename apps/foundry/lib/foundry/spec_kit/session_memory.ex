defmodule Foundry.SpecKit.SessionMemory do
  @moduledoc """
  Extracts durable session findings from assistant responses and persists them as
  canonical spec-kit artifacts under `docs/findings/`.

  The assistant appends a fenced `foundry-memory` JSON block only when a turn
  produced stable technical knowledge worth preserving beyond the current chat.
  Foundry strips that block from the visible response, validates it, and writes
  a markdown artifact that can be indexed alongside ADRs, runbooks, and
  regulations.
  """

  @single_hidden_block_regex ~r/\A```(foundry-memory|foundry-session)\s*(\{.*\})\s*```\z/s
  @memory_block_open "```foundry-memory"
  @session_block_open "```foundry-session"
  @max_list_items 8
  @max_text_length 600

  @type extraction_result :: %{
          response: String.t(),
          payload: map() | nil,
          error: term() | nil
        }

  @spec extract(String.t()) :: extraction_result()
  def extract(response) when is_binary(response) do
    extracted = extract_hidden(response)

    %{
      response: extracted.response,
      payload: extracted.memory.payload,
      error: extracted.memory.error
    }
  end

  @spec extract_hidden(String.t()) :: %{
          response: String.t(),
          memory: %{payload: map() | nil, error: term() | nil},
          session: %{payload: map() | nil, error: term() | nil}
        }
  def extract_hidden(response) when is_binary(response) do
    extract_hidden_blocks(response, %{
      response: response,
      memory: %{payload: nil, error: nil},
      session: %{payload: nil, error: nil}
    })
  end

  @spec persist(String.t(), String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def persist(project_root, session_id, payload, metadata \\ %{})
      when is_binary(project_root) and is_binary(session_id) and is_map(payload) and
             is_map(metadata) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, entry} <- normalize_entry(session_id, payload, metadata, timestamp),
         {:ok, relative_path} <- write_entry(project_root, entry) do
      {:ok,
       %{
         id: entry.id,
         path: relative_path,
         title: entry.title,
         summary: entry.summary,
         tags: entry.tags
       }}
    end
  end

  defp normalize_entry(session_id, payload, metadata, timestamp) do
    summary =
      payload
      |> Map.get("summary")
      |> normalize_text()

    findings = normalize_items(payload["findings"])
    discoveries = normalize_items(payload["discoveries"])
    issues = normalize_items(payload["issues"])
    conclusions = normalize_items(payload["conclusions"] || payload["decisions"])

    if Enum.all?([summary, findings, discoveries, issues, conclusions], &blank_section?/1) do
      {:error, :empty_memory_payload}
    else
      title =
        payload
        |> Map.get("title")
        |> normalize_title(summary, findings, discoveries, issues, conclusions)

      id = build_id(timestamp, session_id, title)

      {:ok,
       %{
         id: id,
         title: title,
         summary: summary || fallback_summary(findings, discoveries, issues, conclusions),
         findings: findings,
         discoveries: discoveries,
         issues: issues,
         conclusions: conclusions,
         related_nodes: normalize_items(payload["related_nodes"]),
         related_docs: normalize_items(payload["related_docs"]),
         tags: normalize_tags(payload["tags"]),
         session_id: session_id,
         mode: metadata["mode"],
         proposal_id: metadata["proposal_id"],
         user_message: normalize_text(metadata["user_message"], 240),
         captured_at: DateTime.to_iso8601(timestamp)
       }}
    end
  end

  defp write_entry(project_root, entry) do
    relative_path = Path.join("docs/findings", "#{entry.id}-#{slugify(entry.title)}.md")
    absolute_path = Path.join(project_root, relative_path)

    with :ok <- File.mkdir_p(Path.dirname(absolute_path)),
         :ok <- File.write(absolute_path, render_markdown(entry)) do
      {:ok, relative_path}
    end
  end

  defp render_markdown(entry) do
    metadata_lines =
      [
        "**Status:** Captured",
        "**Date:** #{entry.captured_at}",
        "**Session:** #{entry.session_id}",
        maybe_metadata_line("Mode", entry.mode),
        maybe_metadata_line("Proposal", entry.proposal_id),
        maybe_metadata_line("Related Nodes", join_list(entry.related_nodes)),
        maybe_metadata_line("Related Docs", join_list(entry.related_docs)),
        maybe_metadata_line("Tags", join_list(entry.tags))
      ]
      |> Enum.reject(&is_nil/1)

    sections =
      [
        section("Summary", entry.summary),
        bullet_section("Technical Findings", entry.findings),
        bullet_section("Important Discoveries", entry.discoveries),
        bullet_section("Issues", entry.issues),
        bullet_section("Conclusions", entry.conclusions),
        section("Source Request", entry.user_message)
      ]
      |> Enum.reject(&(&1 == ""))

    [
      "# #{entry.id}: #{entry.title}",
      "",
      Enum.join(metadata_lines, "  \n"),
      "",
      Enum.join(sections, "\n\n")
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp section(_title, nil), do: ""
  defp section(_title, ""), do: ""

  defp section(title, body) do
    """
    ## #{title}

    #{body}
    """
    |> String.trim()
  end

  defp bullet_section(_title, []), do: ""

  defp bullet_section(title, items) do
    bullets =
      items
      |> Enum.map_join("\n", &"- #{&1}")

    """
    ## #{title}

    #{bullets}
    """
    |> String.trim()
  end

  defp maybe_metadata_line(_label, nil), do: nil
  defp maybe_metadata_line(_label, ""), do: nil
  defp maybe_metadata_line(label, value), do: "**#{label}:** #{value}"

  defp normalize_title(title, summary, findings, discoveries, issues, conclusions) do
    title =
      title
      |> normalize_text(100)

    title ||
      summary ||
      fallback_summary(findings, discoveries, issues, conclusions) ||
      "Session finding"
  end

  defp fallback_summary(findings, discoveries, issues, conclusions) do
    [findings, discoveries, issues, conclusions]
    |> Enum.find_value(fn
      [item | _rest] -> item
      _ -> nil
    end)
  end

  defp normalize_items(nil), do: []

  defp normalize_items(items) when is_list(items) do
    items
    |> Enum.map(&normalize_item/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(@max_list_items)
  end

  defp normalize_items(item), do: normalize_items([item])

  defp normalize_item(%{"text" => text}), do: normalize_text(text)
  defp normalize_item(%{"value" => text}), do: normalize_text(text)
  defp normalize_item(text) when is_binary(text), do: normalize_text(text)
  defp normalize_item(_item), do: nil

  defp normalize_tags(nil), do: []

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&normalize_text(&1, 40))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.take(@max_list_items)
  end

  defp normalize_tags(tag), do: normalize_tags([tag])

  defp normalize_text(text, max_length \\ @max_text_length)

  defp normalize_text(nil, _max_length), do: nil

  defp normalize_text(text, max_length) when is_binary(text) do
    normalized =
      text
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    cond do
      normalized == "" -> nil
      String.length(normalized) > max_length -> String.slice(normalized, 0, max_length)
      true -> normalized
    end
  end

  defp normalize_text(_text, _max_length), do: nil

  defp blank_section?(nil), do: true
  defp blank_section?([]), do: true
  defp blank_section?(""), do: true
  defp blank_section?(_value), do: false

  defp build_id(timestamp, session_id, title) do
    stamp = Calendar.strftime(timestamp, "%Y%m%d-%H%M%S")
    suffix = title |> slugify() |> String.slice(0, 24)

    discriminator =
      :sha256
      |> :crypto.hash(session_id <> ":" <> title)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 6)

    "FND-#{stamp}-#{discriminator}-#{suffix}"
  end

  defp extract_hidden_blocks(response, acc) do
    trimmed_response = String.trim_trailing(response)

    case last_hidden_block_start(trimmed_response) do
      nil ->
        %{acc | response: String.trim_trailing(response)}

      start_index ->
        block =
          binary_part(trimmed_response, start_index, byte_size(trimmed_response) - start_index)

        case Regex.run(@single_hidden_block_regex, block, capture: :all_but_first) do
          [block_type, json] ->
            cleaned_response =
              trimmed_response
              |> binary_part(0, start_index)
              |> String.trim_trailing()

            result =
              case Jason.decode(json) do
                {:ok, payload} when is_map(payload) ->
                  %{payload: payload, error: nil}

                {:ok, _payload} ->
                  %{payload: nil, error: :invalid_payload_shape}

                {:error, reason} ->
                  %{payload: nil, error: {:invalid_json, reason}}
              end

            acc
            |> Map.put(:response, cleaned_response)
            |> put_hidden_result(block_type, result)
            |> then(&extract_hidden_blocks(cleaned_response, &1))

          _ ->
            %{acc | response: String.trim_trailing(response)}
        end
    end
  end

  defp put_hidden_result(acc, "foundry-memory", result), do: Map.put(acc, :memory, result)
  defp put_hidden_result(acc, "foundry-session", result), do: Map.put(acc, :session, result)

  defp last_hidden_block_start(response) do
    response
    |> :binary.matches([@memory_block_open, @session_block_open])
    |> case do
      [] -> nil
      matches -> matches |> Enum.max_by(fn {start_index, _length} -> start_index end) |> elem(0)
    end
  end

  defp slugify(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "session-memory"
      slug -> slug
    end
  end

  defp join_list([]), do: nil
  defp join_list(items), do: Enum.join(items, ", ")
end
