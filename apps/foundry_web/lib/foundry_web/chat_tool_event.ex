defmodule FoundryWeb.ChatToolEvent do
  @moduledoc """
  Normalizes raw trace events (both live atom-keyed and persisted string-keyed)
  into a consistent string-keyed map for rendering in the chat UI.

  The same shape is produced regardless of whether the event comes from an
  in-progress activity run (atom keys, :raw field) or a serialized message
  (string keys, "raw" field).
  """

  @visible_categories ~w(tool file command context proposal error)

  @type normalized :: %{
          String.t() => term()
        }

  @doc """
  Returns true if the event should be shown as an inline tool bubble.
  """
  def visible?(%{category: cat}), do: to_string(cat) in @visible_categories
  def visible?(%{"category" => cat}), do: to_string(cat) in @visible_categories
  def visible?(_), do: false

  @doc """
  Normalizes a single raw event map to a string-keyed display map.
  Works with both atom-keyed (live run) and string-keyed (persisted) events.
  """
  @spec normalize(map()) :: normalized()
  def normalize(event) when is_map(event) do
    cat = event[:category] || event["category"]
    phase = event[:phase] || event["phase"]
    fa = event[:file_access] || event["file_access"]
    raw = event[:raw] || event["raw"] || %{}
    item = Map.get(raw, "item") || %{}

    output =
      Map.get(raw, "output") ||
        Map.get(item, "output") ||
        Map.get(item, "stdout") ||
        Map.get(raw, "result") ||
        Map.get(raw, "content")

    %{
      "category" => to_string(cat),
      "phase" => to_string(phase),
      "tool" => event[:tool] || event["tool"],
      "command" => event[:command] || event["command"],
      "paths" => event[:paths] || event["paths"] || [],
      "file_access" => if(fa, do: to_string(fa), else: nil),
      "title" => event[:title] || event["title"],
      "detail" => event[:detail] || event["detail"],
      "output" => normalize_output(output),
      "count" => event[:count] || event["count"] || 1,
      "text_cursor" => event[:text_cursor] || event["text_cursor"] || 0
    }
  end

  @doc """
  Filters and normalizes a list of grouped trace events for display.
  """
  @spec normalize_many([map()]) :: [normalized()]
  def normalize_many(events) when is_list(events) do
    events
    |> Enum.filter(&visible?/1)
    |> Enum.map(&normalize/1)
  end

  defp normalize_output(output) when is_binary(output) and output != "",
    do: String.slice(output, 0, 2000)

  defp normalize_output(_), do: nil
end
