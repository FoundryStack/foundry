defmodule FoundryWeb.ChatMessageComponents do
  @moduledoc false
  use FoundryWeb, :html

  alias FoundryWeb.ChatToolEvent
  alias FoundryWeb.ChatPathUtils

  attr :message, :map, required: true
  attr :message_index, :integer, required: true
  attr :streaming, :boolean, default: false
  attr :active_run, :map, default: nil
  attr :project_root, :string, default: nil

  def message_bubble(assigns) do
    is_user = assigns.message["role"] == "user"
    active_run = assigns.active_run

    proposal =
      if active_run,
        do: active_run.proposal || assigns.message["proposal"],
        else: assigns.message["proposal"]

    tool_events =
      cond do
        is_user -> []
        active_run != nil -> build_live_tool_events(active_run.grouped_events || [])
        true -> assigns.message["tool_events"] || []
      end

    assigns =
      assigns
      |> assign(:is_user, is_user)
      |> assign(:proposal, proposal)
      |> assign(:tool_events, tool_events)
      |> assign(:delivery_status, assigns.message["delivery_status"])
      |> assign(:content, assigns.message["content"] || "")
      |> assign(:markdown_id, message_markdown_id(assigns.message, assigns.message_index))
      |> assign(:markdown_variant, if(is_user, do: "user", else: "assistant"))
      |> assign(:wrapper_class, if(is_user, do: "flex justify-end", else: "flex justify-start"))
      |> assign(
        :bubble_class,
        if(is_user,
          do: "max-w-[92%] rounded-box bg-primary/8 px-4 py-3 text-base-content shadow-sm",
          else: "max-w-[92%] rounded-box px-4 py-3 text-base-content shadow-sm"
        )
      )

    ~H"""
    <div class={@wrapper_class}>
      <div class={@bubble_class}>
        <div class="mb-2 flex items-center gap-2">
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
            {if @is_user, do: "You", else: "Assistant"}
          </p>
        </div>
        <div class="space-y-2">
          <%= if !@is_user do %>
            <% indexed_tool_events = Enum.with_index(@tool_events) %>
            <% segments = interleave_tool_events(@content, indexed_tool_events, @streaming) %>
            <%= for {{segment_text, segment_events, is_last}, seg_idx} <- Enum.with_index(segments) do %>
              <.inline_tool_event
                :for={{event, global_idx} <- segment_events}
                event={event}
                message_id={@message["id"] || "unknown"}
                event_index={global_idx}
                project_root={@project_root}
              />
              <div
                :if={segment_text != ""}
                class="break-words leading-6"
                data-role="chat-markdown"
                data-variant={@markdown_variant}
              >
                <PhoenixStreamdown.markdown
                  content={segment_text}
                  id={@markdown_id <> if(is_last, do: "", else: "_seg#{seg_idx}")}
                  streaming={is_last && @streaming}
                  theme="github_dark"
                  class="chat-markdown-body"
                  block_class="chat-markdown-block"
                  mdex_opts={markdown_options()}
                />
              </div>
            <% end %>
          <% end %>
          <%= if @is_user do %>
            <div
              :if={@content != ""}
              class="break-words leading-6"
              data-role="chat-markdown"
              data-variant={@markdown_variant}
            >
              <PhoenixStreamdown.markdown
                content={@content}
                id={@markdown_id}
                streaming={@streaming}
                theme="github_dark"
                class="chat-markdown-body"
                block_class="chat-markdown-block"
                mdex_opts={markdown_options()}
              />
            </div>
          <% end %>
          <.proposal_preview_card :if={!@is_user and is_map(@proposal)} proposal={@proposal} />
        </div>
      </div>
    </div>
    """
  end

  attr :proposal, :map, required: true

  def proposal_preview_card(assigns) do
    preview = assigns.proposal[:preview] || assigns.proposal["preview"] || %{}
    files = preview[:files] || preview["files"] || []
    change_summary = preview[:change_summary] || preview["change_summary"] || []
    ui_status = assigns.proposal[:ui_status] || assigns.proposal["ui_status"] || :draft

    assigns =
      assigns
      |> assign(:preview, preview)
      |> assign(:files, files)
      |> assign(:change_summary, change_summary)
      |> assign(:ui_status, ui_status)

    ~H"""
    <section class="mt-4 rounded-box border border-accent/20 bg-neutral/30 p-4">
      <div class="flex flex-wrap items-center gap-2">
        <span class="rounded-full border border-accent/25 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent">
          Proposal {@proposal[:id] || @proposal["id"]}
        </span>
        <span class={proposal_status_class(@ui_status)}>
          {proposal_status_label(@ui_status)}
        </span>
      </div>

      <p class="mt-3 text-sm leading-6 text-base-content/90">
        {@preview[:summary] || @preview["summary"]}
      </p>

      <%= if @change_summary != [] do %>
        <div class="mt-4">
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
            Summary of Changes
          </p>
          <div class="mt-2 space-y-2">
            <p
              :for={summary <- @change_summary}
              class="rounded-box border border-base-300/70 bg-base-100/60 px-3 py-2 text-sm text-base-content/90"
            >
              {summary}
            </p>
          </div>
        </div>
      <% end %>

      <details class="mt-4 overflow-hidden rounded-box border border-base-300/80 bg-[#0d1117]">
        <summary class="cursor-pointer px-3 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-neutral-content">
          Preview Changes
        </summary>
        <div class="border-t border-base-300/80 px-3 py-3">
          <pre class="overflow-x-auto rounded-box bg-[#0d1117] px-3 py-3 font-mono text-[11px] leading-5 text-[#c9d1d9]"><%= @preview[:diff] || @preview["diff"] %></pre>
        </div>
      </details>

      <%= if @files != [] do %>
        <div class="mt-4">
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
            Changed Files
          </p>
          <div class="mt-2 space-y-2">
            <button
              :for={file <- @files}
              type="button"
              phx-click="open_proposal_file_preview"
              phx-value-proposal_id={@proposal[:id] || @proposal["id"]}
              phx-value-path={file[:path] || file["path"]}
              class="flex w-full items-center justify-between rounded-box border border-base-300/70 bg-base-100/60 px-3 py-2 text-left transition-colors hover:border-primary/40 hover:bg-base-100"
            >
              <span class="min-w-0 truncate font-mono text-xs text-base-content">
                {file[:path] || file["path"]}
              </span>
              <span class="ml-3 shrink-0 text-[11px] text-neutral-content">
                {file[:added_lines] || file["added_lines"] || 0}+ / {file[:removed_lines] ||
                  file["removed_lines"] || 0}-
              </span>
            </button>
          </div>
        </div>
      <% end %>

      <div class="mt-4 flex flex-wrap gap-2">
        <button
          type="button"
          phx-click="proposal_apply"
          phx-value-id={@proposal[:id] || @proposal["id"]}
          class="rounded-selector bg-success/90 px-3 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-base-100 transition-opacity hover:opacity-90"
        >
          Apply
        </button>
        <button
          type="button"
          phx-click="proposal_revise"
          phx-value-id={@proposal[:id] || @proposal["id"]}
          class="rounded-selector border border-warning/30 bg-warning/10 px-3 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-warning transition-colors hover:bg-warning/15"
        >
          Revise In Chat
        </button>
        <button
          type="button"
          phx-click="proposal_cancel"
          phx-value-id={@proposal[:id] || @proposal["id"]}
          class="rounded-selector border border-base-300 bg-base-100/70 px-3 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-neutral-content transition-colors hover:text-base-content"
        >
          Cancel
        </button>
      </div>
    </section>
    """
  end

  def thinking_bubble(assigns) do
    ~H"""
    <div class="flex justify-start" data-role="thinking-bubble">
      <div class="max-w-[92%] rounded-box border border-base-300 bg-base-200/80 px-4 py-3 text-base-content shadow-sm">
        <div class="mb-1 flex items-center gap-2">
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
            Assistant
          </p>
          <span class="text-[10px] uppercase tracking-[0.12em] text-neutral-content/70">
            Thinking
          </span>
        </div>
        <div class="foundry-thinking-dots" aria-label="Assistant is thinking">
          <span></span>
          <span></span>
          <span></span>
        </div>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true
  attr :message_id, :string, required: true
  attr :event_index, :integer, default: 0
  attr :project_root, :string, default: nil

  def inline_tool_event(assigns) do
    # Generate unique id using hash of event content + indices to avoid collisions
    # This ensures multiple identical events still get unique DOM ids
    event_hash = :crypto.hash(:md5, inspect(assigns.event)) |> Base.encode16() |> String.slice(0..7)
    event_id = "tool-#{assigns.message_id}-#{assigns.event_index}-#{event_hash}"
    assigns = assign(assigns, :event_id, event_id)

    ~H"""
    <details id={@event_id} class="group pl-3 border-l-2 border-white/10 hover:border-white/20 transition-colors">
      <summary class="flex cursor-pointer list-none items-center gap-2 py-0.5 select-none">
        <span class={inline_tool_icon_class(@event["category"])}>
          {inline_tool_icon(@event["category"])}
        </span>
        <span class="min-w-0 flex-1 truncate text-[12px] text-base-content/60 group-open:text-base-content/80">
          {format_tool_title(@event)}
        </span>
        <span :if={(@event["count"] || 1) > 1} class="shrink-0 text-[10px] text-neutral-content/40">
          ×{@event["count"]}
        </span>
        <svg class="shrink-0 h-3 w-3 text-neutral-content/30 transition-transform group-open:rotate-90" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
        </svg>
      </summary>
      <div class="mt-1 ml-1 space-y-1.5 pb-1">
        <pre
          :if={@event["output"]}
          class="whitespace-pre-wrap break-all font-mono text-[11px] leading-5 text-neutral-content/50"
        >{@event["output"]}</pre>
        <pre
          :if={!@event["output"] && @event["detail"]}
          class="whitespace-pre-wrap break-all font-mono text-[11px] leading-5 text-neutral-content/50"
        >{@event["detail"]}</pre>
        <div :if={(@event["paths"] || []) != []} class="flex flex-wrap gap-1">
          <%= for path <- Enum.take(@event["paths"] || [], 6) do %>
            <% {rel_path, line} = ChatPathUtils.parse_path_ref(path, @project_root) %>
            <button
              :if={rel_path != nil}
              phx-click="fetch_file"
              phx-value-path={rel_path}
              phx-value-line={line}
              class={["cursor-pointer hover:opacity-80 active:opacity-60", inline_tool_path_class(@event["file_access"])]}
            >
              {ChatPathUtils.path_tail(path)}
            </button>
            <span
              :if={rel_path == nil}
              class={inline_tool_path_class(@event["file_access"])}
            >
              {ChatPathUtils.path_tail(path)}
            </span>
          <% end %>
          <span
            :if={length(@event["paths"] || []) > 6}
            class="rounded px-1 py-0.5 text-[10px] text-neutral-content/40"
          >
            +{length(@event["paths"]) - 6} more
          </span>
        </div>
      </div>
    </details>
    """
  end

  # --- Private helpers ---

  @inline_tool_icons %{
    "tool" => "⚙",
    "command" => ">",
    "file" => "□",
    "context" => "◈",
    "proposal" => "◉",
    "error" => "!"
  }
  defp inline_tool_icon(cat), do: Map.get(@inline_tool_icons, cat, "·")

  @inline_tool_icon_classes %{
    "tool" => "shrink-0 text-[11px] text-secondary/70",
    "command" => "shrink-0 text-[11px] font-mono text-base-content/50",
    "file" => "shrink-0 text-[11px] text-info/70",
    "context" => "shrink-0 text-[11px] text-accent/70",
    "proposal" => "shrink-0 text-[11px] text-success/70",
    "error" => "shrink-0 text-[11px] text-error/70"
  }
  defp inline_tool_icon_class(cat),
    do: Map.get(@inline_tool_icon_classes, cat, "shrink-0 text-[11px] text-neutral-content/40")

  defp format_tool_title(event) do
    tool = event["tool"]
    command = event["command"]
    category = event["category"]
    paths = event["paths"] || []
    first_path = List.first(paths)

    cond do
      tool == "module_context" and first_path ->
        "Read module #{first_path}"

      tool == "module_context" ->
        "Read module context"

      tool == "read_doc" and first_path ->
        "Read doc #{Path.basename(first_path)}"

      tool == "read_doc" ->
        "Read document"

      tool in ["apply_patch", "write_file", "create_file"] and first_path ->
        "Write #{ChatPathUtils.path_tail(first_path)}"

      tool in ["read_file", "cat", "open"] and first_path ->
        "Read #{ChatPathUtils.path_tail(first_path)}"

      category == "command" and is_binary(command) ->
        inner = strip_shell_wrapper(command)
        "Shell #{String.slice(inner, 0, 100)}"

      is_binary(tool) and tool != "" ->
        "Tool: #{tool}"

      true ->
        event["title"] || event["command"] || category || "Tool activity"
    end
  end

  defp strip_shell_wrapper(command) do
    case Regex.run(~r{/bin/(?:ba|z)?sh\s+-\w+\s+"(.+)"$}s, command) do
      [_, inner] ->
        String.trim(inner)

      _ ->
        case Regex.run(~r{/bin/(?:ba|z)?sh\s+-\w+\s+'(.+)'$}s, command) do
          [_, inner] -> String.trim(inner)
          _ -> command
        end
    end
  end

  defp inline_tool_path_class("write"),
    do:
      "rounded border border-warning/20 bg-warning/10 px-1.5 py-0.5 font-mono text-[10px] text-warning"

  defp inline_tool_path_class(_),
    do: "rounded border border-info/20 bg-info/10 px-1.5 py-0.5 font-mono text-[10px] text-info"

  # Returns [{text_segment, [{event, global_idx}, ...], is_last_segment}]
  # Accepts tool_events as {event, global_idx} tuples from Enum.with_index
  defp interleave_tool_events(content, indexed_tool_events, _streaming) do
    sorted_events = Enum.sort_by(indexed_tool_events, fn {event, _idx} -> event["text_cursor"] || 0 end)
    grouped = Enum.group_by(sorted_events, fn {event, _idx} -> event["text_cursor"] || 0 end)

    split_cursors = grouped |> Map.keys() |> Enum.filter(&(&1 > 0)) |> Enum.sort()

    events_at_zero = Map.get(grouped, 0, [])

    {pairs, remaining_text, _offset} =
      Enum.reduce(split_cursors, {[], content, 0}, fn cursor, {acc, rest, offset} ->
        raw_pos = max(0, min(cursor - offset, String.length(rest)))
        local_pos = ChatPathUtils.snap_to_word_boundary(rest, raw_pos)
        {before, after_text} = String.split_at(rest, local_pos)
        events_here = Map.get(grouped, cursor, [])
        {acc ++ [{before, events_here}], after_text, offset + local_pos}
      end)

    case pairs do
      [] ->
        [{content, events_at_zero, true}]

      _ ->
        first_text = elem(List.first(pairs), 0)
        first = {first_text, events_at_zero, false}

        middle =
          pairs
          |> Enum.drop(1)
          |> Enum.zip(pairs |> Enum.map(&elem(&1, 1)))
          |> Enum.map(fn {{text, _}, events_before} -> {text, events_before, false} end)

        last_events = elem(List.last(pairs), 1)
        last = {remaining_text, last_events, true}

        [first | middle] ++ [last]
    end
  end

  defp build_live_tool_events(grouped_events) do
    ChatToolEvent.normalize_many(grouped_events)
  end

  defp message_markdown_id(message, index) do
    timestamp = Map.get(message, "timestamp", "message")
    "chat-message-#{index}-#{timestamp}"
  end

  defp markdown_options do
    [
      extension: [
        autolink: true,
        strikethrough: true,
        table: true,
        tasklist: true
      ],
      parse: [
        relaxed_autolinks: true,
        relaxed_tasklist_matching: true,
        smart: true
      ],
      render: [
        escape: true,
        unsafe: true
      ]
    ]
  end

  @proposal_status_labels %{
    applied: "Applied",
    awaiting_revision: "Awaiting revision",
    cancelled: "Cancelled"
  }

  defp proposal_status_label(status) when is_atom(status),
    do: Map.get(@proposal_status_labels, status, "Draft")

  defp proposal_status_label(status) when is_binary(status), do: status
  defp proposal_status_label(_), do: "Draft"

  @proposal_status_classes %{
    applied:
      "rounded-full border border-success/25 bg-success/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-success",
    awaiting_revision:
      "rounded-full border border-warning/25 bg-warning/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-warning",
    cancelled:
      "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"
  }
  @badge_accent "rounded-full border border-accent/25 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent"

  defp proposal_status_class(status), do: Map.get(@proposal_status_classes, status, @badge_accent)
end
