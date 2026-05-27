defmodule FoundryWeb.ChatPathUtils do
  @moduledoc """
  Path and text utilities shared between chat components and the chat session layer.

  - `parse_path_ref/2`  — resolve a raw path string to a {relative_path, line} tuple
  - `path_tail/1`       — last 1-2 path segments for display
  - `snap_to_word_boundary/2` — find a safe split point that avoids mid-word cuts
  """

  @doc """
  Returns `{relative_path, line_number | nil}` for a raw path string.

  Strips the `project_root` prefix when present (absolute paths).
  Parses `#L<n>` anchors for line numbers.
  Returns `{nil, nil}` when the input is not recognizable as a file path
  (e.g. Elixir module IDs like `"IgamingRef.Finance.LedgerEntry"`).
  """
  @spec parse_path_ref(String.t() | nil, String.t() | nil) :: {String.t() | nil, integer() | nil}
  def parse_path_ref(nil, _project_root), do: {nil, nil}
  def parse_path_ref("", _project_root), do: {nil, nil}

  def parse_path_ref(path, project_root) when is_binary(path) do
    {base_path, anchor} =
      case String.split(path, "#", parts: 2) do
        [base, anchor] -> {base, anchor}
        [base] -> {base, nil}
      end

    # Module IDs like "IgamingRef.Finance.LedgerEntry" are not file paths —
    # a real file path must contain "/" or end in a recognizable file extension.
    if not file_path?(base_path) do
      {nil, nil}
    else
      line =
        case anchor do
          "L" <> n ->
            case Integer.parse(n) do
              {line_num, ""} -> line_num
              _ -> nil
            end

          _ ->
            nil
        end

      rel =
        cond do
          is_binary(project_root) and String.starts_with?(base_path, project_root) ->
            base_path
            |> String.slice(String.length(project_root)..-1//1)
            |> String.trim_leading("/")

          not String.starts_with?(base_path, "/") ->
            base_path

          true ->
            nil
        end

      if rel && rel != "", do: {rel, line}, else: {nil, nil}
    end
  end

  def parse_path_ref(path, project_root), do: parse_path_ref(to_string(path), project_root)

  @doc """
  Returns the last 1-2 path segments for compact display in path badges.
  Strips any `#L<n>` anchor before computing the tail.
  """
  @spec path_tail(String.t() | term()) :: String.t()
  def path_tail(path) when is_binary(path) do
    base = path |> String.split("#") |> List.first()
    base |> String.split("/") |> Enum.take(-2) |> Enum.join("/")
  end

  def path_tail(path), do: to_string(path)

  @doc """
  Snaps a character offset backwards to the nearest preceding newline or
  whitespace boundary to avoid mid-word splits when inserting tool event dividers.
  """
  @spec snap_to_word_boundary(String.t(), non_neg_integer()) :: non_neg_integer()
  def snap_to_word_boundary(_text, pos) when pos <= 0, do: 0

  def snap_to_word_boundary(text, pos) do
    prefix = String.slice(text, 0, pos)

    case Regex.run(~r/[\n\r]\s*$|[\s]+$/, prefix, return: :index) do
      [{match_start, _}] -> match_start
      _ -> pos
    end
  end

  # --- Private ---

  defp file_path?(base_path) do
    String.contains?(base_path, "/") or Regex.match?(~r/\.[a-z]{1,6}$/i, base_path)
  end
end
