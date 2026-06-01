defmodule FoundryWeb.ChatTraceComponents do
  @moduledoc false
  use FoundryWeb, :html

  alias Foundry.ChatTrace
  alias FoundryWeb.ChatTokenMeter

  attr :activity_runs, :list, required: true
  attr :selected_run, :map, default: nil
  attr :chat_loading, :boolean, required: true

  def trace_panel(assigns) do
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

  def session_panel(assigns) do
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
            title="Recent outcomes"
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

  # --- Private helpers ---

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
        case Map.get(diagnostics, :context_cache) do
          "hit" -> "Context cached"
          "miss" -> "Context rebuilt"
          cache_status when is_binary(cache_status) -> cache_status
          _ -> "n/a"
        end

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

  defp run_total_tokens(run) when is_map(run), do: Map.get(run, :total_tokens)
  defp run_total_tokens(_run), do: nil

  defp summary_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%H:%M:%S UTC")
      _ -> value
    end
  end

  defp summary_timestamp(_value), do: "just now"

  defp provider_label(nil), do: "Default"

  defp provider_label(provider) do
    FoundryWeb.ChatModelCatalog.pretty_provider_label(provider)
  end

  @trace_status_classes %{
    running:
      "rounded-full border border-info/25 bg-info/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-info",
    completed:
      "rounded-full border border-success/25 bg-success/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-success",
    error:
      "rounded-full border border-error/25 bg-error/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-error"
  }
  @badge_neutral "rounded-full border border-base-300 bg-base-200 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"

  defp trace_status_class(status), do: Map.get(@trace_status_classes, status, @badge_neutral)

  @trace_category_labels %{
    proposal: "Proposal",
    context: "Context",
    session: "Session",
    tool: "Tool",
    command: "Command",
    file: "File",
    reasoning: "Reasoning",
    message: "Message",
    result: "Result",
    error: "Error"
  }

  defp trace_category_label(category),
    do: Map.get(@trace_category_labels, category, "Event")

  @trace_category_classes %{
    proposal:
      "rounded-full border border-accent/20 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent",
    context:
      "rounded-full border border-info/20 bg-info/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-info",
    session:
      "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content",
    tool:
      "rounded-full border border-secondary/20 bg-secondary/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-secondary",
    command:
      "rounded-full border border-primary/20 bg-primary/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-primary",
    file:
      "rounded-full border border-accent/20 bg-accent/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-accent",
    error:
      "rounded-full border border-error/20 bg-error/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-error"
  }
  @badge_base "rounded-full border border-base-300 bg-base-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content"

  defp trace_category_class(category),
    do: Map.get(@trace_category_classes, category, @badge_base)
end
