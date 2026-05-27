defmodule FoundryWeb.ChatComponents do
  @moduledoc false
  use FoundryWeb, :html

  alias Foundry.ChatTrace
  alias FoundryWeb.ChatToolEvent
  alias FoundryWeb.ChatTokenMeter
  alias FoundryWeb.ChatPathUtils

  attr :open_session_ids, :list, default: []
  attr :active_session_id, :string, default: nil
  attr :sessions_by_id, :map, default: %{}
  attr :messages, :list, required: true
  attr :chat_loading, :boolean, required: true
  attr :error, :string, default: nil
  attr :project_root, :string, required: true
  attr :show_system_context, :boolean, required: true
  attr :system_context_prompt, :string, default: nil
  attr :system_context_error, :string, default: nil
  attr :selected_model, :map, default: nil
  attr :model_catalog, :list, default: []
  attr :llm_diagnostics, :map, default: %{}
  attr :chat_view, :atom, default: :conversation
  attr :activity_runs, :list, default: []
  attr :selected_activity_run_id, :integer, default: nil
  attr :session_digest, :map, default: %{}
  attr :input, :string, default: ""
  attr :last_session_summary_at, :string, default: nil

  def studio_panel(assigns) do
    selected_run = selected_run(assigns.activity_runs, assigns.selected_activity_run_id)

    token_meter =
      ChatTokenMeter.build(
        assigns.messages,
        assigns.session_digest,
        assigns.input,
        assigns.llm_diagnostics
      )

    assigns =
      assigns
      |> assign(:selected_run, selected_run)
      |> assign(:latest_run, List.first(assigns.activity_runs))
      |> assign(:message_count, length(assigns.messages))
      |> assign(:token_meter, token_meter)

    ~H"""
    <section
      id="studio-chat-panel"
      phx-hook="StudioChat"
      data-project-root={@project_root}
      class="flex h-full min-h-0 flex-1 flex-col overflow-hidden"
    >
      <%= if @open_session_ids != [] do %>
        <div class="flex min-h-0 shrink-0 items-center gap-0.5 overflow-x-auto px-3">
          <%= for id <- @open_session_ids do %>
            <% session = Map.get(@sessions_by_id, id, %{})
            title = session["title"] || "Session"
            is_active = id == @active_session_id %>
            <div class={[
              "group flex min-w-0 max-w-[180px] shrink-0 items-center gap-1 border-0 border-b-2 border-transparent bg-transparent px-3 py-2 text-[11px] font-medium uppercase tracking-[0.04em] transition-colors",
              if(is_active,
                do: "border-primary text-gray-100",
                else: "text-gray-100/72 hover:bg-white/8 hover:text-gray-100"
              )
            ]}>
              <button
                class="min-w-0 flex-1 truncate text-left"
                phx-click="chat_session_switch"
                phx-value-id={id}
              >
                {title}
              </button>
              <button
                class="shrink-0 text-neutral-content opacity-0 transition-opacity group-hover:opacity-100 hover:text-base-content pl-2"
                phx-click="chat_session_close"
                phx-value-id={id}
                title="Close tab"
              >
                ×
              </button>
            </div>
          <% end %>
          <button
            class="ml-1 shrink-0 rounded-selector border border-transparent bg-transparent px-2 py-1.5 text-lg font-medium uppercase rounded-[50%] text-gray-100/72 transition-colors hover:bg-white/8 hover:text-gray-100"
            phx-click="chat_session_new"
            title="New session"
          >
            +
          </button>
        </div>
      <% else %>
        <div class="flex shrink-0 items-center justify-between px-3 py-2">
          <button
            class="rounded-selector px-2 py-1.5 text-[11px] font-medium uppercase tracking-[0.04em] text-gray-100/72 transition-colors hover:bg-white/8 hover:text-gray-100"
            phx-click="chat_session_new"
          >
            + New session
          </button>
        </div>
      <% end %>
      <%= if @show_system_context do %>
        <div class="border-b border-white/10 px-4 py-3">
          <div class="rounded-[18px] border border-white/10 bg-transparent">
            <div class="flex items-center justify-between gap-3 border-b border-white/10 px-3 py-2">
              <p class="text-xs font-semibold uppercase tracking-[0.12em] text-neutral-content">
                System Context Prompt
              </p>
              <%= if @system_context_prompt do %>
                <p class="text-[11px] text-neutral-content">
                  {byte_size(@system_context_prompt)} bytes
                </p>
              <% end %>
            </div>

            <%= if @system_context_error do %>
              <p class="px-3 py-3 text-sm whitespace-pre-wrap text-error">{@system_context_error}</p>
            <% else %>
              <pre class="max-h-52 overflow-auto px-3 py-3 text-[11px] leading-5 whitespace-pre-wrap text-base-content/85"><%= @system_context_prompt %></pre>
            <% end %>
          </div>
        </div>
      <% end %>

        <div class="flex h-full min-h-0 flex-col overflow-hidden rounded-[22px]">
          <div class="px-4 py-3">
            <div class="flex items-center justify-between gap-3">
              <div class="inline-flex rounded-2xl text-xs uppercase text-neutral-content">
                <button
                  type="button"
                  phx-click="set_chat_view"
                  phx-value-view="conversation"
                  class={chat_tab_class(@chat_view == :conversation)}
                >
                  Conversation
                </button>
                <button
                  type="button"
                  phx-click="set_chat_view"
                  phx-value-view="trace"
                  class={chat_tab_class(@chat_view == :trace)}
                >
                  Trace
                </button>
                <button
                  type="button"
                  phx-click="set_chat_view"
                  phx-value-view="session"
                  class={chat_tab_class(@chat_view == :session)}
                >
                  Session
                </button>
              </div>

              <button
                type="button"
                phx-click="toggle_system_context"
                class="shrink-0 rounded-2xl border border-white/10 bg-transparent px-3 py-2 text-xs font-medium text-neutral-content transition-colors hover:border-white/8 hover:bg-white/8 hover:text-base-content"
              >
                {if @show_system_context, do: "Hide context", else: "Show context"}
              </button>
            </div>
          </div>

          <%= if @chat_view == :conversation do %>
            <div class="min-h-0 flex-1 overflow-y-auto px-4 py-4">
              <div id="studio-chat-conversation" class="space-y-3" aria-live="polite">
                <%= if Enum.empty?(@messages) do %>
                  <div class="rounded-[18px] border border-dashed border-white/10 bg-transparent px-4 py-6 text-center">
                    <p class="text-sm font-medium text-base-content">
                      Start a governed project conversation.
                    </p>
                    <p class="mt-1 text-xs leading-5 text-neutral-content">
                      Ask for explanations in `ask` mode, or request implementation work and Foundry will route the run into proposal-backed `change` mode.
                    </p>
                  </div>
                <% end %>

                <%= for {msg, index} <- Enum.with_index(@messages) do %>
                  <.message_bubble
                    message={msg}
                    message_index={index}
                    streaming={streaming_message?(msg, index, @message_count, @chat_loading)}
                    active_run={message_active_run(msg, index, @message_count, @chat_loading, @latest_run)}
                    project_root={@project_root}
                  />
                <% end %>

                <.thinking_bubble :if={thinking_visible?(@messages, @chat_loading)} />
              </div>
            </div>
          <% end %>

          <%= if @chat_view == :trace do %>
            <.trace_panel
              activity_runs={@activity_runs}
              selected_run={@selected_run}
              chat_loading={@chat_loading}
            />
          <% end %>

          <%= if @chat_view == :session do %>
            <.session_panel
              session_digest={@session_digest}
              selected_run={@selected_run}
              chat_loading={@chat_loading}
              last_session_summary_at={@last_session_summary_at}
            />
          <% end %>

          <%= if @error do %>
            <div class="border-t border-error/20 bg-error/10 px-4 py-3 text-sm whitespace-pre-wrap text-error">
              {@error}
            </div>
          <% end %>

          <% grouped_catalog = family_groups(@model_catalog) %>
          <form
            id="studio-chat-form"
            phx-submit="send_message"
            class="border-t border-white/8 bg-transparent px-4 py-4"
          >
            <div>
              <textarea
                id="chat-message-studio"
                name="message"
                rows="3"
                placeholder="Ask about the system, or request a change..."
                data-role="chat-input"
                class="w-full resize-none rounded-[18px] border border-white/10 bg-transparent px-3 py-3 text-sm leading-6 text-base-content outline-none backdrop-blur-sm placeholder:text-neutral-content/50"
              ><%= @input %></textarea>
              <% active_proposal_id = @session_digest["active_proposal_id"]
              active_proposal_status = @session_digest["active_proposal_status"]

              show_proposal_actions =
                is_binary(active_proposal_id) and
                  active_proposal_status not in ["applied", "cancelled"] %>
              <%= if show_proposal_actions do %>
                <div class="mt-2 flex items-center gap-2">
                  <p class="text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content">
                    Active proposal:
                  </p>
                  <button
                    type="button"
                    phx-click="proposal_apply"
                    phx-value-id={active_proposal_id}
                    disabled={@chat_loading}
                    class="rounded-selector bg-success/90 px-2.5 py-1.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-base-100 transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Apply
                  </button>
                  <button
                    type="button"
                    phx-click="proposal_revise"
                    phx-value-id={active_proposal_id}
                    disabled={@chat_loading}
                    class="rounded-selector border border-warning/30 bg-warning/10 px-2.5 py-1.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-warning transition-colors hover:bg-warning/15 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Revise
                  </button>
                  <button
                    type="button"
                    phx-click="proposal_cancel"
                    phx-value-id={active_proposal_id}
                    disabled={@chat_loading}
                    class="rounded-selector border border-base-300 bg-base-100/70 px-2.5 py-1.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content transition-colors hover:text-base-content disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Cancel
                  </button>
                </div>
              <% end %>
              <div class="mt-3 flex items-center justify-between gap-3">
                <div class="flex items-center gap-2">
                  <div class="relative inline-flex w-auto max-w-[125px] flex-none items-center rounded-2xl border border-white/10 bg-transparent pr-7">
                    <select
                      id="model-select"
                      name="model"
                      phx-change="set_chat_model"
                      class="w-auto min-w-[90px] max-w-[125px] flex-none appearance-none bg-transparent px-3 py-2 text-[11px] font-medium text-gray-100 outline-none focus:outline-none"
                    >
                      <optgroup :for={{family_label, entries} <- grouped_catalog} label={family_label}>
                        <option
                          :for={entry <- entries}
                          value={entry.id}
                          selected={@selected_model && @selected_model.id == entry.id}
                          disabled={entry.availability != :available}
                        >
                          {entry.label}
                          <%= if entry.availability != :available and is_binary(entry.disabled_reason) do %>
                            {" - " <> entry.disabled_reason}
                          <% end %>
                        </option>
                      </optgroup>
                    </select>
                    <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-[10px] text-neutral-content">
                      ▾
                    </span>
                  </div>
                </div>
                <div class="flex items-center justify-end flex-1 gap-2">
                  <button
                    type="button"
                    phx-click="summarize_session"
                    disabled={@chat_loading}
                    title={ChatTokenMeter.title(@token_meter)}
                    class="group relative grid h-10 w-10 place-items-center rounded-full border border-base-300/80 bg-base-200/70 transition-opacity hover:opacity-80 disabled:cursor-not-allowed disabled:opacity-50"
                    data-role="token-meter-summarize"
                    style={ChatTokenMeter.ring_style(@token_meter)}
                  >
                    <div class="grid h-7 w-7 place-items-center rounded-full bg-base-100/95 text-[9px] font-semibold uppercase tracking-[0.08em] text-base-content">
                      {ChatTokenMeter.ring_label(@token_meter)}
                    </div>
                    <div class="pointer-events-none absolute bottom-full left-1/2 mb-2 hidden w-48 -translate-x-1/2 rounded-box border border-base-300 bg-base-100 px-3 py-2 text-[10px] text-base-content shadow-lg group-hover:block">
                      <p class="font-semibold uppercase tracking-[0.12em] text-neutral-content">
                        {ChatTokenMeter.summary(@token_meter)}
                      </p>
                      <p class="mt-1 text-xs leading-4 text-base-content/70">
                        Click to summarize session
                      </p>
                      <div class="pointer-events-none absolute -bottom-1 left-1/2 -translate-x-1/2 size-2 -rotate-45 border-r border-t border-base-300 bg-base-100">
                      </div>
                    </div>
                  </button>
                </div>
                  <%= if @chat_loading do %>
                    <button
                      type="button"
                      phx-click="cancel_message"
                      class="inline-flex items-center rounded-2xl border border-warning/30 bg-warning/10 px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-warning transition-colors hover:bg-warning/15"
                    >
                      Stop
                    </button>
                  <% else %>
                    <button
                      type="submit"
                      class="inline-flex items-center rounded-2xl border border-white/15 bg-white px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-neutral transition-colors hover:bg-gray-100"
                    >
                      Send
                    </button>
                  <% end %>
              </div>
            </div>
          </form>
        </div>


    </section>
    """
  end

  attr :activity_runs, :list, required: true
  attr :selected_run, :map, default: nil
  attr :chat_loading, :boolean, required: true

  defp trace_panel(assigns) do
    ~H"""
    <div class="grid min-h-0 flex-1 grid-cols-[14rem_minmax(0,1fr)]">
      <aside class="min-h-0 overflow-y-auto border-r border-base-300/80 bg-base-200/50">
        <%= if Enum.empty?(@activity_runs) do %>
          <div class="px-4 py-6 text-center">
            <p class="text-sm font-medium text-base-content">No trace yet.</p>
            <p class="mt-1 text-xs leading-5 text-neutral-content">
              Send a message to capture retrieval, proposal, and provider activity.
            </p>
          </div>
        <% else %>
          <div class="space-y-2 p-3">
            <%= for run <- @activity_runs do %>
              <button
                type="button"
                phx-click="select_activity_run"
                phx-value-id={run.id}
                class={trace_run_class(@selected_run && @selected_run.id == run.id)}
              >
                <div class="flex items-start justify-between gap-2">
                  <p class="line-clamp-2 text-xs font-semibold leading-5 text-base-content">
                    {run.user_message}
                  </p>
                  <span class={trace_status_class(run.status)}>{status_label(run.status)}</span>
                </div>
                <div class="mt-2 flex flex-wrap gap-1">
                  <span class={mode_badge_class(run.mode)}>{mode_label(run.mode)}</span>
                  <%= if proposal_id = get_in(run, [:proposal, :id]) do %>
                    <span class="rounded-full border border-accent/25 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold text-accent">
                      {proposal_id}
                    </span>
                  <% end %>
                </div>
                <p class="mt-2 text-[11px] text-neutral-content">
                  {run.grouped_event_count || 0} grouped • {run.tool_count} tools • {run.file_count} files
                </p>
              </button>
            <% end %>
          </div>
        <% end %>
      </aside>

      <div class="min-h-0 overflow-y-auto bg-base-100/30">
        <%= if @selected_run do %>
            <div class="rounded-box border border-base-300/80 bg-base-100/85 p-4">
              <div class="flex items-start justify-between gap-3">
                <div>
                  <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
                    Trace Summary
                  </p>
                  <h2 class="mt-1 text-sm font-semibold leading-6 text-base-content">
                    {@selected_run.user_message}
                  </h2>
                </div>
              </div>

              <div class="mt-4 grid grid-cols-2 gap-2 xl:grid-cols-4">
                <.trace_stat label="Mode" value={mode_label(@selected_run.mode)} />
                <.trace_stat label="Provider" value={provider_label(@selected_run.provider)} />
                <.trace_stat label="Grouped events" value={@selected_run.grouped_event_count || 0} />
                <.trace_stat label="Sandbox" value={trace_sandbox(@selected_run)} />
              </div>

              <div class="mt-4 grid grid-cols-2 gap-2 xl:grid-cols-5">
                <.trace_stat label="Context cache" value={trace_cache_label(@selected_run)} />
                <.trace_stat
                  label="Context reused"
                  value={yes_no(get_in(@selected_run, [:provenance, :cached_context_used]))}
                />
                <.trace_stat
                  label="Foundry tools"
                  value={yes_no(get_in(@selected_run, [:provenance, :foundry_tools_used]))}
                />
                <.trace_stat
                  label="Shell retrieval"
                  value={yes_no(get_in(@selected_run, [:provenance, :shell_retrieval_used]))}
                />
                <.trace_stat
                  label="True fallback"
                  value={yes_no(trace_true_fallback_used(@selected_run))}
                />
                <.trace_stat
                  label="Global refetches"
                  value={get_in(@selected_run, [:provenance, :redundant_global_context_fetches]) || 0}
                />
              </div>

              <div class="mt-2 grid grid-cols-2 gap-2 xl:grid-cols-2">
                <.trace_stat
                  label="Proposal flow"
                  value={yes_no(get_in(@selected_run, [:provenance, :proposal_flow_used]))}
                />
                <.trace_stat label="Files surfaced" value={@selected_run.file_count} />
                <.trace_stat label="Read files" value={length(@selected_run.read_files || [])} />
                <.trace_stat
                  label="Written files"
                  value={length(@selected_run.written_files || [])}
                />
                <.trace_stat label="Tokens" value={run_total_tokens(@selected_run) || "n/a"} />
              </div>

              <%= if (get_in(@selected_run, [:provenance, :redundant_global_context_fetches]) || 0) > 0 do %>
                <p class="mt-3 rounded-box border border-warning/20 bg-warning/10 px-3 py-2 text-xs leading-5 text-warning-content">
                  This run re-requested already injected global context.
                </p>
              <% end %>

              <%= if @selected_run.files != [] do %>
                <div class="mt-4">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.12em] text-neutral-content">
                    Surfaced files
                  </p>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <%= for path <- Enum.take(@selected_run.files, 12) do %>
                      <span class="rounded-full border border-base-300 bg-base-200/80 px-2.5 py-1 font-mono text-[11px] text-base-content/80">
                        {path}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @selected_run.written_files != [] do %>
                <div class="mt-4">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.12em] text-neutral-content">
                    Written files
                  </p>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <%= for path <- Enum.take(@selected_run.written_files, 12) do %>
                      <span class="rounded-full border border-warning/25 bg-warning/10 px-2.5 py-1 font-mono text-[11px] text-warning">
                        {path}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @selected_run.tools != [] do %>
                <div class="mt-4">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.12em] text-neutral-content">
                    Tools used
                  </p>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <%= for tool <- @selected_run.tools do %>
                      <span class="rounded-full border border-secondary/20 bg-secondary/10 px-2.5 py-1 text-[11px] font-semibold text-secondary">
                        {tool}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>

            <div class="rounded-box border border-base-300/80 bg-base-100/85 p-4">
              <div class="flex items-center justify-between gap-3">
                <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
                  Event Timeline
                </p>
                <p class="text-[11px] text-neutral-content">
                  {if @chat_loading, do: "Streaming live", else: "Grouped by phase"}
                </p>
              </div>

              <div class="mt-4 space-y-4">
                <%= for phase_group <- @selected_run.phase_groups || [] do %>
                  <section class="rounded-box border border-base-300/80 bg-base-200/35">
                    <div class="flex items-center justify-between border-b border-base-300/80 px-4 py-3">
                      <div class="flex items-center gap-2">
                        <span class="rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content">
                          {ChatTrace.phase_label(phase_group.phase)}
                        </span>
                        <p class="text-sm font-semibold text-base-content">
                          {phase_group.count} grouped events
                        </p>
                      </div>
                    </div>

                    <div class="space-y-3 p-4">
                      <%= for event <- phase_group.events do %>
                        <details class="group rounded-box border border-base-300/80 bg-base-100/80 p-3">
                          <summary class="flex cursor-pointer list-none items-start justify-between gap-3">
                            <div class="min-w-0">
                              <div class="flex flex-wrap items-center gap-2">
                                <span class={trace_category_class(event.category)}>
                                  {trace_category_label(event.category)}
                                </span>
                                <p class="text-sm font-medium text-base-content">{event.title}</p>
                                <%= if event.count > 1 do %>
                                  <span class="rounded-full border border-base-300 bg-base-200 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content">
                                    {event.count}x
                                  </span>
                                <% end %>
                              </div>
                              <p class="mt-1 text-xs leading-5 text-neutral-content">
                                {event.detail}
                              </p>
                            </div>
                            <span class="text-[10px] uppercase tracking-[0.12em] text-neutral-content">
                              Raw
                            </span>
                          </summary>

                          <%= if event.paths != [] do %>
                            <div class="mt-3 flex flex-wrap gap-2">
                              <%= for path <- event.paths do %>
                                <span class="rounded-full border border-base-300 bg-base-100/80 px-2 py-1 font-mono text-[11px] text-base-content/80">
                                  {path}
                                </span>
                              <% end %>
                            </div>
                          <% end %>

                          <pre class="mt-3 overflow-x-auto rounded-box border border-base-300/80 bg-neutral/90 px-3 py-3 text-[11px] leading-5 text-neutral-content"><%= ChatTrace.pretty_raw(event) %></pre>
                        </details>
                      <% end %>
                    </div>
                  </section>
                <% end %>
              </div>
            </div>

            <%= if @selected_run.error do %>
              <div class="rounded-box border border-error/30 bg-error/10 px-4 py-3 text-sm text-error">
                {@selected_run.error}
              </div>
            <% end %>

        <% else %>
          <div class="px-4 py-6 text-center">
            <p class="text-sm font-medium text-base-content">Trace inspection is ready.</p>
            <p class="mt-1 text-xs leading-5 text-neutral-content">
              Foundry retrieval, proposal flow, and provider events will appear here after the first message.
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :session_digest, :map, default: %{}
  attr :selected_run, :map, default: nil
  attr :chat_loading, :boolean, required: true
  attr :last_session_summary_at, :string, default: nil

  defp session_panel(assigns) do
    ~H"""
    <div class="min-h-0 flex-1 overflow-y-auto bg-base-100/30 p-4">
      <div class="space-y-4">
        <div class="rounded-box border border-base-300/80 bg-base-100/85 p-4">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
                Session Memory
              </p>
              <p class="mt-2 text-sm leading-6 text-base-content">
                The Studio copilot keeps a compact digest across turns instead of replaying the full project context every time.
              </p>
            </div>
            <%= if @last_session_summary_at do %>
              <p class="text-[11px] text-neutral-content">
                Updated {summary_timestamp(@last_session_summary_at)}
              </p>
            <% end %>
          </div>

          <div class="mt-4 grid grid-cols-1 gap-3 xl:grid-cols-2">
            <.digest_card label="Last mode" value={Map.get(@session_digest, "last_mode", "n/a")} />
            <.digest_card
              label="Context fingerprint"
              value={Map.get(@session_digest, "context_fingerprint", "n/a")}
              mono
            />
            <.digest_card
              label="Context cache"
              value={Map.get(@session_digest, "context_cache", "n/a")}
            />
            <.digest_card
              label="Last proposal"
              value={Map.get(@session_digest, "last_proposal_id", "none")}
            />
            <.digest_card
              label="Recent tokens"
              value={ChatTokenMeter.usage_label(Map.get(@session_digest, "recent_token_usage", %{}))}
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
          <.digest_list
            title="Working summary"
            items={List.wrap(Map.get(@session_digest, "working_summary"))}
          />
          <.digest_list
            title="Selected nodes"
            items={Map.get(@session_digest, "selected_nodes", [])}
            mono
          />
          <.digest_list
            title="Recent documents"
            items={Map.get(@session_digest, "recent_documents", [])}
            mono
          />
          <.digest_list
            title="Saved findings"
            items={Map.get(@session_digest, "recent_findings", [])}
          />
          <.digest_list
            title="Recent conclusions"
            items={Map.get(@session_digest, "recent_conclusions", [])}
          />
          <.digest_list
            title="Recent read files"
            items={Map.get(@session_digest, "recent_read_files", [])}
            mono
          />
          <.digest_list
            title="Recent written files"
            items={Map.get(@session_digest, "recent_written_files", [])}
            mono
          />
        </div>

        <%= if trace_summary = Map.get(@session_digest, "recent_trace_summary") do %>
          <div class="rounded-box border border-base-300/80 bg-base-100/85 p-4">
            <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
              Last Trace Summary
            </p>
            <pre class="mt-3 overflow-x-auto rounded-box border border-base-300/80 bg-neutral/90 px-3 py-3 text-[11px] leading-5 text-neutral-content"><%= Jason.encode!(trace_summary, pretty: true) %></pre>
          </div>
        <% end %>

        <%= if @selected_run do %>
          <div class="rounded-box border border-base-300/80 bg-base-200/40 p-4">
            <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
              Active Run Snapshot
            </p>
            <p class="mt-2 text-sm leading-6 text-base-content">
              {mode_label(@selected_run.mode)} mode with {@selected_run.grouped_event_count || 0} grouped trace events and {length(
                @selected_run.files || []
              )} surfaced files.
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp trace_stat(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300/80 bg-base-200/55 px-3 py-2">
      <p class="text-[10px] uppercase tracking-[0.12em] text-neutral-content/70">{@label}</p>
      <p class="mt-1 text-xs font-semibold text-base-content">{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :mono, :boolean, default: false

  defp digest_card(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300/80 bg-base-200/45 px-3 py-3">
      <p class="text-[10px] uppercase tracking-[0.12em] text-neutral-content/70">{@label}</p>
      <p class={["mt-1 text-xs font-semibold text-base-content", @mono && "font-mono break-all"]}>
        {@value}
      </p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, default: []
  attr :mono, :boolean, default: false

  defp digest_list(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300/80 bg-base-100/85 p-4">
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
        {@title}
      </p>
      <%= if @items == [] do %>
        <p class="mt-3 text-sm text-neutral-content">Nothing stored yet.</p>
      <% else %>
        <div class="mt-3 space-y-2">
          <%= for item <- @items do %>
            <div class={[
              "rounded-box border border-base-300/80 bg-base-200/40 px-3 py-2 text-sm text-base-content",
              @mono && "font-mono break-all text-[12px]"
            ]}>
              {item}
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :message, :map, required: true
  attr :message_index, :integer, required: true
  attr :streaming, :boolean, default: false
  attr :active_run, :map, default: nil
  attr :project_root, :string, default: nil

  defp message_bubble(assigns) do
    is_user = assigns.message["role"] == "user"
    active_run = assigns.active_run

    proposal =
      if active_run, do: active_run.proposal || assigns.message["proposal"], else: assigns.message["proposal"]

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
            <% segments = interleave_tool_events(@content, @tool_events, @streaming) %>
            <%= for {{segment_text, segment_events, is_last}, seg_idx} <- Enum.with_index(segments) do %>
              <.inline_tool_event
                :for={event <- segment_events}
                event={event}
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

  defp proposal_preview_card(assigns) do
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

  defp thinking_bubble(assigns) do
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
  attr :project_root, :string, default: nil

  defp inline_tool_event(assigns) do
    ~H"""
    <details class="group pl-3 border-l-2 border-white/10 hover:border-white/20 transition-colors">
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

  @inline_tool_icons %{"tool" => "⚙", "command" => ">", "file" => "□", "context" => "◈", "proposal" => "◉", "error" => "!"}
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
      [_, inner] -> String.trim(inner)
      _ ->
        case Regex.run(~r{/bin/(?:ba|z)?sh\s+-\w+\s+'(.+)'$}s, command) do
          [_, inner] -> String.trim(inner)
          _ -> command
        end
    end
  end

  defp inline_tool_path_class("write"),
    do: "rounded border border-warning/20 bg-warning/10 px-1.5 py-0.5 font-mono text-[10px] text-warning"

  defp inline_tool_path_class(_),
    do: "rounded border border-info/20 bg-info/10 px-1.5 py-0.5 font-mono text-[10px] text-info"


  # Returns [{text_segment, [tool_events_preceding_segment], is_last_segment}]
  # Each tuple means: render the tool events, then render the text segment.
  # The last segment is flagged so the caller can set streaming=true on it.
  defp interleave_tool_events(content, tool_events, _streaming) do
    sorted_events = Enum.sort_by(tool_events, &(&1["text_cursor"] || 0))
    grouped = Enum.group_by(sorted_events, &(&1["text_cursor"] || 0))

    # Collect the unique cursor positions where text should be split
    split_cursors = grouped |> Map.keys() |> Enum.filter(&(&1 > 0)) |> Enum.sort()

    events_at_zero = Map.get(grouped, 0, [])

    # Build list of {text_before_split, events_at_split} pairs.
    # Snap split position to nearest preceding newline or whitespace to avoid mid-word breaks.
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
        # No mid-text splits: all events at cursor 0, render before full text
        [{content, events_at_zero, true}]

      _ ->
        # First segment: events_at_zero before the first piece of text
        first_text = elem(List.first(pairs), 0)
        first = {first_text, events_at_zero, false}

        # Middle segments: events from position N before the text chunk after position N
        middle =
          pairs
          |> Enum.drop(1)
          |> Enum.zip(pairs |> Enum.map(&elem(&1, 1)))
          |> Enum.map(fn {{text, _}, events_before} -> {text, events_before, false} end)

        # Last segment: events from the last split before the remaining tail text
        last_events = elem(List.last(pairs), 1)
        last = {remaining_text, last_events, true}

        [first | middle] ++ [last]
    end
  end

  defp build_live_tool_events(grouped_events) do
    ChatToolEvent.normalize_many(grouped_events)
  end

  defp streaming_message?(%{"role" => "assistant"}, index, message_count, true),
    do: index == message_count - 1

  defp streaming_message?(_message, _index, _message_count, _loading), do: false

  defp message_active_run(%{"role" => "assistant"}, index, message_count, true, latest_run)
       when index == message_count - 1,
       do: latest_run

  defp message_active_run(_message, _index, _message_count, _loading, _latest_run), do: nil

  defp thinking_visible?(messages, true) do
    case List.last(messages) do
      %{"role" => "assistant", "content" => content} -> String.trim(content || "") == ""
      _ -> true
    end
  end

  defp thinking_visible?(_messages, _loading), do: false

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

  defp provider_label(nil), do: "Default"

  defp provider_label(provider) do
    FoundryWeb.ChatModelCatalog.pretty_provider_label(provider)
  end

  defp family_groups(catalog), do: FoundryWeb.ChatModelCatalog.family_groups(catalog)

  defp selected_run([], _selected_id), do: nil

  defp selected_run(runs, selected_id) do
    Enum.find(runs, &(selected_id && &1.id == selected_id)) || List.first(runs)
  end

  defp chat_tab_class(true) do
    "rounded-xl border border-white/10 bg-white/10 px-3 py-1.5 font-semibold text-md shadow-sm backdrop-blur-sm"
  end

  defp chat_tab_class(false) do
    "rounded-xl border border-transparent px-3 py-1.5 font-semibold text-md text-neutral-content transition-colors hover:bg-white/6 hover:text-base-content"
  end

  defp trace_run_class(true) do
    "w-full rounded-box border border-primary/40 bg-primary/10 px-3 py-3 text-left shadow-sm"
  end

  defp trace_run_class(false) do
    "w-full rounded-box border border-base-300/80 bg-base-100/80 px-3 py-3 text-left transition-colors hover:border-primary/40 hover:bg-base-100"
  end

  defp mode_label(:change), do: "Change"
  defp mode_label(_), do: "Ask"

  defp mode_badge_class(:change),
    do:
      "inline-flex items-center rounded-full border border-warning/25 bg-warning/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-warning"

  defp mode_badge_class(_),
    do:
      "inline-flex items-center rounded-full border border-info/25 bg-info/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-info"

  defp status_label(:running), do: "Running"
  defp status_label(:completed), do: "Completed"
  defp status_label(:error), do: "Errored"
  defp status_label(_status), do: "Idle"

  defp trace_sandbox(run) when is_map(run) do
    run
    |> Map.get(:diagnostics, %{})
    |> case do
      diagnostics when is_map(diagnostics) -> Map.get(diagnostics, :sandbox, "n/a") || "n/a"
      _ -> "n/a"
    end
  end

  defp trace_sandbox(_run), do: "n/a"

  defp trace_cache_label(run) when is_map(run) do
    run
    |> Map.get(:diagnostics, %{})
    |> case do
      diagnostics when is_map(diagnostics) ->
        Map.get(diagnostics, :context_cache, "n/a") || "n/a"

      _ ->
        "n/a"
    end
  end

  defp trace_cache_label(_run), do: "n/a"

  defp trace_true_fallback_used(run) when is_map(run) do
    get_in(run, [:provenance, :true_fallback_used]) ||
      get_in(run, [:provenance, :shell_fallback_used])
  end

  defp trace_true_fallback_used(_run), do: false

  defp yes_no(true), do: "Yes"
  defp yes_no(false), do: "No"
  defp yes_no(nil), do: "No"

  defp run_total_tokens(run) when is_map(run),
    do: Map.get(run, :total_tokens)

  defp run_total_tokens(_run), do: nil

  defp summary_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%H:%M:%S UTC")
      _ -> value
    end
  end

  defp summary_timestamp(_value), do: "just now"

  @trace_status_classes %{
    running: "rounded-full border border-info/25 bg-info/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-info",
    completed: "rounded-full border border-success/25 bg-success/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-success",
    error: "rounded-full border border-error/25 bg-error/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-error"
  }
  @badge_neutral "rounded-full border border-base-300 bg-base-200 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"

  defp trace_status_class(status), do: Map.get(@trace_status_classes, status, @badge_neutral)

  @proposal_status_labels %{applied: "Applied", awaiting_revision: "Awaiting revision", cancelled: "Cancelled"}

  defp proposal_status_label(status) when is_atom(status),
    do: Map.get(@proposal_status_labels, status, "Draft")

  defp proposal_status_label(status) when is_binary(status), do: status
  defp proposal_status_label(_), do: "Draft"

  @proposal_status_classes %{
    applied: "rounded-full border border-success/25 bg-success/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-success",
    awaiting_revision: "rounded-full border border-warning/25 bg-warning/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-warning",
    cancelled: "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"
  }
  @badge_accent "rounded-full border border-accent/25 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent"

  defp proposal_status_class(status), do: Map.get(@proposal_status_classes, status, @badge_accent)

  @trace_category_labels %{
    proposal: "Proposal", context: "Context", session: "Session", tool: "Tool",
    command: "Command", file: "File", reasoning: "Reasoning", message: "Message",
    result: "Result", error: "Error"
  }

  defp trace_category_label(category),
    do: Map.get(@trace_category_labels, category, "Event")

  @trace_category_classes %{
    proposal: "rounded-full border border-accent/20 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent",
    context: "rounded-full border border-info/20 bg-info/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-info",
    session: "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content",
    tool: "rounded-full border border-secondary/20 bg-secondary/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-secondary",
    command: "rounded-full border border-primary/20 bg-primary/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-primary",
    file: "rounded-full border border-accent/20 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent",
    error: "rounded-full border border-error/20 bg-error/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-error"
  }
  @badge_base "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"

  defp trace_category_class(category),
    do: Map.get(@trace_category_classes, category, @badge_base)
end
