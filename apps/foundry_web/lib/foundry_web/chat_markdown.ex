defmodule FoundryWeb.ChatMarkdown do
  @moduledoc false

  import Phoenix.HTML

  @inline_pattern ~r/`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)/

  def to_html(content, opts \\ []) when is_binary(content) do
    content
    |> parse_blocks()
    |> Enum.map(&render_block(&1, opts))
    |> IO.iodata_to_binary()
  end

  defp parse_blocks(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> do_parse([], nil)
    |> Enum.reverse()
  end

  defp do_parse([], acc, nil), do: acc

  defp do_parse([], acc, {:paragraph, lines}),
    do: [{:paragraph, Enum.reverse(lines)} | acc]

  defp do_parse([], acc, {:list, items}),
    do: [{:list, Enum.reverse(items)} | acc]

  defp do_parse([], acc, {:code, lang, lines}),
    do: [{:code, lang, Enum.reverse(lines) |> Enum.join("\n")} | acc]

  defp do_parse([line | rest], acc, {:code, lang, lines}) do
    if String.starts_with?(line, "```") do
      do_parse(rest, [{:code, lang, Enum.reverse(lines) |> Enum.join("\n")} | acc], nil)
    else
      do_parse(rest, acc, {:code, lang, [line | lines]})
    end
  end

  defp do_parse([line | rest], acc, current) do
    cond do
      String.starts_with?(line, "```") ->
        {acc, _current} = flush_current(acc, current)
        lang = line |> String.trim_leading("```") |> String.trim()
        do_parse(rest, acc, {:code, blank_to_nil(lang), []})

      heading = parse_heading(line) ->
        {acc, current} = flush_current(acc, current)
        do_parse(rest, [heading | acc], current)

      list_item = parse_list_item(line) ->
        do_parse_list(rest, acc, current, [list_item])

      String.trim(line) == "" ->
        {acc, current} = flush_current(acc, current)
        do_parse(rest, acc, current)

      true ->
        do_parse(rest, acc, append_paragraph_line(current, line))
    end
  end

  defp do_parse_list(rest, acc, current, items) do
    {acc, current} = flush_current(acc, current)

    case rest do
      [line | next] ->
        case parse_list_item(line) do
          nil -> do_parse(rest, [{:list, Enum.reverse(items)} | acc], current)
          item -> do_parse_list(next, acc, current, [item | items])
        end

      [] ->
        do_parse([], [{:list, Enum.reverse(items)} | acc], current)
    end
  end

  defp flush_current(acc, nil), do: {acc, nil}

  defp flush_current(acc, {:paragraph, lines}),
    do: {[{:paragraph, Enum.reverse(lines)} | acc], nil}

  defp flush_current(acc, {:list, items}),
    do: {[{:list, Enum.reverse(items)} | acc], nil}

  defp append_paragraph_line(nil, line), do: {:paragraph, [line]}
  defp append_paragraph_line({:paragraph, lines}, line), do: {:paragraph, [line | lines]}

  defp parse_heading(line) do
    trimmed = String.trim_leading(line)
    markers = trimmed |> String.graphemes() |> Enum.take_while(&(&1 == "#"))
    marker_count = length(markers)

    cond do
      marker_count == 0 or marker_count > 6 ->
        nil

      true ->
        prefix = String.duplicate("#", marker_count)

        case String.trim_leading(trimmed, prefix) do
          <<" ", rest::binary>> ->
            rest = String.trim(rest)

            if rest == "" do
              nil
            else
              {:heading, marker_count, rest}
            end

          _ ->
            nil
        end
    end
  end

  defp parse_list_item(line) do
    case Regex.run(~r/^\s*[-*]\s+(.+)$/, line) do
      [_, item] -> item
      _ -> nil
    end
  end

  defp render_block({:heading, level, text}, opts) do
    tag = String.to_atom("h#{min(level, 4)}")
    open_tag(tag, class: "mb-2 font-semibold tracking-[0.01em] text-base-content #{heading_size_class(level)}") <>
      render_inline(text, opts) <>
      close_tag(tag)
  end

  defp render_block({:paragraph, lines}, opts) do
    content =
      lines
      |> Enum.map(&render_inline(&1, opts))
      |> Enum.intersperse("<br>")

    open_tag(:p, class: "text-sm leading-6 text-inherit") <>
      IO.iodata_to_binary(content) <>
      close_tag(:p)
  end

  defp render_block({:list, items}, opts) do
    rendered_items =
      Enum.map(items, fn item ->
        open_tag(:li, class: "ml-5 list-disc pl-1 text-sm leading-6 text-inherit") <>
          render_inline(item, opts) <>
          close_tag(:li)
      end)

    open_tag(:ul, class: "space-y-1") <> IO.iodata_to_binary(rendered_items) <> close_tag(:ul)
  end

  defp render_block({:code, lang, code}, _opts) do
    badge =
      if lang do
        open_tag(:div,
          class:
            "border-b border-base-300/70 px-3 py-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-neutral-content/80"
        ) <>
          escape_html(String.upcase(lang)) <> close_tag(:div)
      else
        nil
      end

    code_block =
      open_tag(:pre, class: "overflow-x-auto") <>
        open_tag(:code,
          class: "block overflow-x-auto px-3 py-3 font-mono text-[12px] leading-6 text-base-content"
        ) <>
        escape_html(code) <>
        close_tag(:code) <>
        close_tag(:pre)

    open_tag(:div, class: "overflow-hidden rounded-box border border-base-300/80 bg-base-300/40") <>
      IO.iodata_to_binary([badge, code_block]) <>
      close_tag(:div)
  end

  defp render_inline(text, opts) do
    variant = Keyword.get(opts, :variant, :assistant)

    text
    |> then(&Regex.split(@inline_pattern, &1, include_captures: true, trim: false))
    |> Enum.map(&render_inline_segment(&1, variant))
    |> IO.iodata_to_binary()
  end

  defp render_inline_segment("", _variant), do: ""

  defp render_inline_segment(segment, variant) do
    cond do
      Regex.match?(~r/^`[^`]+`$/, segment) ->
        <<"`", code::binary>> = segment
        code = String.trim_trailing(code, "`")
        open_tag(:code, class: inline_code_class(variant)) <> escape_html(code) <> close_tag(:code)

      Regex.match?(~r/^\[[^\]]+\]\([^)]+\)$/, segment) ->
        case Regex.run(~r/^\[([^\]]+)\]\(([^)]+)\)$/, segment) do
          [_, label, url] ->
            case safe_url(url) do
              nil ->
                escape_html(segment)

              safe ->
                open_tag(:a,
                  href: safe,
                  target: "_blank",
                  rel: "noreferrer noopener",
                  class: inline_link_class(variant)
                ) <> escape_html(label) <> close_tag(:a)
            end

          _ ->
            escape_html(segment)
        end

      true ->
        escape_html(segment)
    end
  end

  defp safe_url(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https", "mailto"] do
      url
    end
  rescue
    _ -> nil
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp heading_size_class(1), do: "text-lg"
  defp heading_size_class(2), do: "text-base"
  defp heading_size_class(3), do: "text-sm"
  defp heading_size_class(_), do: "text-sm"

  defp inline_code_class(:user) do
    "rounded bg-primary/20 px-1.5 py-0.5 font-mono text-[12px] text-primary-content"
  end

  defp inline_code_class(_) do
    "rounded bg-base-300/70 px-1.5 py-0.5 font-mono text-[12px] text-base-content"
  end

  defp inline_link_class(:user) do
    "font-medium text-primary-content underline decoration-primary/60 underline-offset-4"
  end

  defp inline_link_class(_) do
    "font-medium text-secondary underline decoration-secondary/70 underline-offset-4"
  end

  defp escape_html(value) do
    value
    |> html_escape()
    |> safe_to_string()
  end

  defp open_tag(name, attrs) do
    attr_html =
      attrs
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join("", fn {key, value} ->
        " #{key}=\"#{escape_html(to_string(value))}\""
      end)

    "<#{name}#{attr_html}>"
  end

  defp close_tag(name), do: "</#{name}>"
end
