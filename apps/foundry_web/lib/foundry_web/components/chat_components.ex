defmodule FoundryWeb.ChatComponents do
  @moduledoc false
  use FoundryWeb, :html

  alias Foundry.ChatTrace

  attr :messages, :list, required: true
  attr :loading, :boolean, required: true
  attr :error, :string, default: nil
  attr :project_root, :string, required: true
  attr :show_system_context, :boolean, required: true
  attr :system_context_prompt, :string, default: nil
  attr :system_context_error, :string, default: nil
  attr :llm_provider, :any, default: nil
  attr :llm_diagnostics, :map, default: %{}
  attr :chat_view, :atom, default: :conversation
  attr :activity_runs, :list, default: []
  attr :selected_activity_run_id, :integer, default: nil
  attr :session_digest, :map, default: %{}

  def studio_panel(assigns) do
    selected_run = selected_run(assigns.activity_runs, assigns.selected_activity_run_id)

    assigns =
      assigns
      |> assign(:selected_run, selected_run)
      |> assign(:latest_run, List.first(assigns.activity_runs))
      |> assign(:message_count, length(assigns.messages))

    ~H"""
    <section
      id="studio-chat-panel"
      phx-hook="StudioChat"
      data-project-root={@project_root}
      class="flex h-full min-h-0 flex-1 flex-col overflow-hidden bg-base-200/30"
    >
      <div class="border-b border-base-300/80 px-4 py-2">
        <div class="flex items-start justify-between gap-3">
          <div class="space-y-1">
            <div class="flex flex-wrap items-center gap-2">
              <%= if @latest_run do %>
                <span class={mode_badge_class(@latest_run.mode)}>
                  {mode_label(@latest_run.mode)}
                </span>
                <%= if proposal_id = get_in(@latest_run, [:proposal, :id]) do %>
                  <span class="inline-flex items-center rounded-full border border-accent/25 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent">
                    proposal {proposal_id}
                  </span>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-2 xl:grid-cols-[minmax(0,1fr)_auto]">
          <%= if @latest_run do %>
            <div class="grid grid-cols-3 gap-2">
              <.trace_stat label="Last run" value={status_label(@latest_run.status)} />
              <.trace_stat label="Grouped trace" value={@latest_run.grouped_event_count || 0} />
              <.trace_stat label="Files surfaced" value={@latest_run.file_count} />
            </div>
          <% end %>
        </div>
      </div>

      <%= if @show_system_context do %>
        <div class="border-b border-base-300/80 px-4 py-3">
          <div class="rounded-box border border-base-300/80 bg-base-300/35">
            <div class="flex items-center justify-between gap-3 border-b border-base-300/80 px-3 py-2">
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

      <div class="min-h-0 flex-1 px-4 pb-4">
        <div class="flex h-full min-h-0 flex-col rounded-box border border-base-300/80 bg-base-100/70 shadow-[0_18px_60px_rgba(0,0,0,0.12)]">
          <div>
            <div class="flex items-center justify-between gap-3">
              <div class="inline-flex rounded-selector border border-base-300 bg-base-200/80 p-1">
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
            class="shrink-0 rounded-selector border border-base-300 bg-base-300/70 px-3 py-2 text-xs font-medium text-neutral-content transition-colors hover:border-primary/40 hover:bg-base-300 hover:text-base-content"
          >
            {if @show_system_context, do: "Hide context", else: "Show context"}
          </button>
            </div>
          </div>

          <%= if @chat_view == :conversation do %>
            <div class="min-h-0 flex-1 overflow-y-auto">
              <div id="studio-chat-conversation" class="space-y-3" aria-live="polite">
                <%= if Enum.empty?(@messages) do %>
                  <div class="rounded-box border border-dashed border-base-300 bg-base-200/50 px-4 py-6 text-center">
                    <p class="text-sm font-medium text-base-content">
                      Start a governed project conversation.
                    </p>
                    <p class="mt-1 text-xs leading-5 text-neutral-content">
                      Ask for explanations in `ask` mode, or request implementation work and Foundry will route the run into proposal-backed `change` mode.
                    </p>
                  </div>
                <% end %>

                <%= if @latest_run do %>
                  <div class="rounded-box border border-base-300/80 bg-base-200/55 px-4 py-3">
                    <div class="flex flex-wrap items-center gap-2">
                      <span class={mode_badge_class(@latest_run.mode)}>
                        {mode_label(@latest_run.mode)}
                      </span>
                      <span class={trace_status_class(@latest_run.status)}>
                        {status_label(@latest_run.status)}
                      </span>
                      <%= if proposal_id = get_in(@latest_run, [:proposal, :id]) do %>
                        <span class="rounded-full border border-accent/25 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent">
                          Proposal {proposal_id}
                        </span>
                      <% end %>
                    </div>
                    <p class="mt-2 text-xs leading-5 text-neutral-content">
                      Context cache {trace_cache_label(@latest_run)}. Foundry retrieval runs before shell fallback, and governed change requests are attached to proposal metadata.
                    </p>
                  </div>
                <% end %>

                <%= for {msg, index} <- Enum.with_index(@messages) do %>
                  <.message_bubble
                    message={msg}
                    message_index={index}
                    streaming={streaming_message?(msg, index, @message_count, @loading)}
                  />
                <% end %>

                <%= if @loading do %>
                  <div class="max-w-[90%] rounded-box border border-base-300 bg-base-200/80 px-4 py-3 text-sm text-neutral-content shadow-sm">
                    Thinking...
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @chat_view == :trace do %>
            <.trace_panel
              activity_runs={@activity_runs}
              selected_run={@selected_run}
              loading={@loading}
            />
          <% end %>

          <%= if @chat_view == :session do %>
            <.session_panel session_digest={@session_digest} selected_run={@selected_run} />
          <% end %>

          <%= if @error do %>
            <div class="border-t border-error/20 bg-error/10 px-4 py-3 text-sm whitespace-pre-wrap text-error">
              {@error}
            </div>
          <% end %>

          <form
            id="studio-chat-form"
            phx-submit="send_message"
            class="border-t border-base-300/80 px-4 py-4"
          >
            <div>
              <label
                for="chat-message-studio"
                class="mb-2 block text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content"
              >
                Message
              </label>
              <textarea
                id="chat-message-studio"
                name="message"
                rows="3"
                placeholder="Ask about the system, or request a change..."
                data-role="chat-input"
                class="w-full resize-none border-0 bg-transparent px-0 py-0 text-sm leading-6 text-base-content outline-none placeholder:text-neutral-content/50"
                disabled={@loading}
              ></textarea>
              <div class="mt-3 flex items-center justify-between gap-3">
                <p class="text-[11px] leading-5 text-neutral-content">
                                <span class="inline-flex items-center gap-1 rounded-full border border-base-300 bg-base-300/70 px-2 py-0.5 text-[10px] uppercase tracking-[0.12em] text-neutral-content">
                <span class="size-1.5 rounded-full bg-success"></span>
                {provider_label(@llm_provider)}
              </span>
                </p>
                <button
                  type="submit"
                  disabled={@loading}
                  class="inline-flex items-center rounded-selector bg-primary px-3 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-primary-content transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  Send
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </section>
    """
  end

  attr :activity_runs, :list, required: true
  attr :selected_run, :map, default: nil
  attr :loading, :boolean, required: true

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
          <div class="space-y-4 p-4">
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
                <span class={trace_status_class(@selected_run.status)}>
                  {status_label(@selected_run.status)}
                </span>
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
                  label="Foundry tools"
                  value={yes_no(get_in(@selected_run, [:provenance, :foundry_tools_used]))}
                />
                <.trace_stat
                  label="Shell fallback"
                  value={yes_no(get_in(@selected_run, [:provenance, :shell_fallback_used]))}
                />
                <.trace_stat
                  label="Proposal flow"
                  value={yes_no(get_in(@selected_run, [:provenance, :proposal_flow_used]))}
                />
                <.trace_stat label="Files surfaced" value={@selected_run.file_count} />
              </div>

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
                  {if @loading, do: "Streaming live", else: "Grouped by phase"}
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
          </div>
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

  defp session_panel(assigns) do
    ~H"""
    <div class="min-h-0 flex-1 overflow-y-auto bg-base-100/30 p-4">
      <div class="space-y-4">
        <div class="rounded-box border border-base-300/80 bg-base-100/85 p-4">
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
            Session Memory
          </p>
          <p class="mt-2 text-sm leading-6 text-base-content">
            The Studio copilot keeps a compact digest across turns instead of replaying the full project context every time.
          </p>

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
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
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
            title="Recent files"
            items={Map.get(@session_digest, "recent_files", [])}
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

  defp message_bubble(assigns) do
    is_user = assigns.message["role"] == "user"
    proposal = assigns.message["proposal"]

    assigns =
      assigns
      |> assign(:is_user, is_user)
      |> assign(:proposal, proposal)
      |> assign(:content, assigns.message["content"] || "")
      |> assign(:markdown_id, message_markdown_id(assigns.message, assigns.message_index))
      |> assign(:markdown_variant, if(is_user, do: "user", else: "assistant"))
      |> assign(:wrapper_class, if(is_user, do: "flex justify-end", else: "flex justify-start"))
      |> assign(
        :bubble_class,
        if(is_user,
          do:
            "max-w-[92%] rounded-box border border-primary/25 bg-primary/12 px-4 py-3 text-primary-content/95 shadow-sm",
          else:
            "max-w-[92%] rounded-box border border-base-300 bg-base-200/80 px-4 py-3 text-base-content shadow-sm"
        )
      )

    ~H"""
    <div class={@wrapper_class}>
      <div class={@bubble_class}>
        <div class="mb-1 flex items-center gap-2">
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">
            {if @is_user, do: "You", else: "Assistant"}
          </p>
        </div>
        <div
          class="space-y-3 break-words text-sm leading-6"
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
        <.proposal_preview_card :if={!@is_user and is_map(@proposal)} proposal={@proposal} />
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
            <p :for={summary <- @change_summary} class="rounded-box border border-base-300/70 bg-base-100/60 px-3 py-2 text-sm text-base-content/90">
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
                {file[:added_lines] || file["added_lines"] || 0}+ / {file[:removed_lines] || file["removed_lines"] || 0}-
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

  defp streaming_message?(%{"role" => "assistant"}, index, message_count, true),
    do: index == message_count - 1

  defp streaming_message?(_message, _index, _message_count, _loading), do: false

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
        escape: true
      ]
    ]
  end

  defp provider_label(nil), do: "Default"

  defp provider_label(provider) do
    provider
    |> to_string()
    |> String.replace("_", " ")
  end

  defp selected_run([], _selected_id), do: nil

  defp selected_run(runs, selected_id) do
    Enum.find(runs, &(selected_id && &1.id == selected_id)) || List.first(runs)
  end

  defp chat_tab_class(true) do
    "rounded-selector bg-base-100 px-3 py-1.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-base-content shadow-sm"
  end

  defp chat_tab_class(false) do
    "rounded-selector px-3 py-1.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-neutral-content transition-colors hover:text-base-content"
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

  defp yes_no(true), do: "Yes"
  defp yes_no(false), do: "No"
  defp yes_no(nil), do: "No"

  defp trace_status_class(:running),
    do:
      "rounded-full border border-info/25 bg-info/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-info"

  defp trace_status_class(:completed),
    do:
      "rounded-full border border-success/25 bg-success/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-success"

  defp trace_status_class(:error),
    do:
      "rounded-full border border-error/25 bg-error/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-error"

  defp trace_status_class(_status),
    do:
      "rounded-full border border-base-300 bg-base-200 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"

  defp proposal_status_label(:applied), do: "Applied"
  defp proposal_status_label(:awaiting_revision), do: "Awaiting revision"
  defp proposal_status_label(:cancelled), do: "Cancelled"
  defp proposal_status_label(status) when is_binary(status), do: status
  defp proposal_status_label(_status), do: "Draft"

  defp proposal_status_class(:applied),
    do:
      "rounded-full border border-success/25 bg-success/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-success"

  defp proposal_status_class(:awaiting_revision),
    do:
      "rounded-full border border-warning/25 bg-warning/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-warning"

  defp proposal_status_class(:cancelled),
    do:
      "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"

  defp proposal_status_class(_status),
    do:
      "rounded-full border border-accent/25 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent"

  defp trace_category_label(:proposal), do: "Proposal"
  defp trace_category_label(:context), do: "Context"
  defp trace_category_label(:session), do: "Session"
  defp trace_category_label(:tool), do: "Tool"
  defp trace_category_label(:command), do: "Command"
  defp trace_category_label(:file), do: "File"
  defp trace_category_label(:reasoning), do: "Reasoning"
  defp trace_category_label(:message), do: "Message"
  defp trace_category_label(:result), do: "Result"
  defp trace_category_label(:error), do: "Error"
  defp trace_category_label(_category), do: "Event"

  defp trace_category_class(:proposal),
    do:
      "rounded-full border border-accent/20 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent"

  defp trace_category_class(:context),
    do:
      "rounded-full border border-info/20 bg-info/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-info"

  defp trace_category_class(:session),
    do:
      "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"

  defp trace_category_class(:tool),
    do:
      "rounded-full border border-secondary/20 bg-secondary/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-secondary"

  defp trace_category_class(:command),
    do:
      "rounded-full border border-primary/20 bg-primary/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-primary"

  defp trace_category_class(:file),
    do:
      "rounded-full border border-accent/20 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent"

  defp trace_category_class(:error),
    do:
      "rounded-full border border-error/20 bg-error/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-error"

  defp trace_category_class(_category),
    do:
      "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"
end
