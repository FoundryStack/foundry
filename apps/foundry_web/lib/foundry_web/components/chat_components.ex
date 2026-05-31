defmodule FoundryWeb.ChatComponents do
  @moduledoc false
  use FoundryWeb, :html

  alias FoundryWeb.ChatTokenMeter

  import FoundryWeb.ChatMessageComponents
  import FoundryWeb.ChatTraceComponents
  import FoundryWeb.ChatInputComponents

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
        <div class="flex min-h-0 shrink-0 items-center gap-0.5 px-3">
          <div class="flex flex-row flex-1 min-w-0 overflow-x-auto">
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
          </div>
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
          <!-- View Toggle Buttons -->
          <div class="flex gap-1 border-b border-white/10 px-3 py-2 shrink-0">
            <button
              phx-click="set_chat_view"
              phx-value-view="conversation"
              class={[
                "px-3 py-1.5 rounded text-xs font-medium uppercase tracking-wider transition-colors",
                if(@chat_view == :conversation,
                  do: "bg-primary text-primary-content",
                  else: "bg-white/10 text-gray-100/72 hover:bg-white/20"
                )
              ]}
            >
              💬 Conversation
            </button>
            <button
              phx-click="set_chat_view"
              phx-value-view="trace"
              class={[
                "px-3 py-1.5 rounded text-xs font-medium uppercase tracking-wider transition-colors",
                if(@chat_view == :trace,
                  do: "bg-primary text-primary-content",
                  else: "bg-white/10 text-gray-100/72 hover:bg-white/20"
                )
              ]}
            >
              🔍 Debug Trace
            </button>
            <button
              phx-click="set_chat_view"
              phx-value-view="session"
              class={[
                "px-3 py-1.5 rounded text-xs font-medium uppercase tracking-wider transition-colors",
                if(@chat_view == :session,
                  do: "bg-primary text-primary-content",
                  else: "bg-white/10 text-gray-100/72 hover:bg-white/20"
                )
              ]}
            >
              📋 Session
            </button>
          </div>

          <%= if @chat_view == :conversation do %>
            <div class="min-h-0 flex-1 overflow-y-auto px-4 py-4">
              <div id="studio-chat-conversation" class="space-y-3" aria-live="polite">
                <%= if Enum.empty?(@messages) do %>
                  <div data-role="welcome-block" class="rounded-[18px] border border-dashed border-white/10 bg-transparent px-4 py-6 text-center">
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

          <.chat_input_form
            input={@input}
            chat_loading={@chat_loading}
            selected_model={@selected_model}
            model_catalog={@model_catalog}
            session_digest={@session_digest}
            token_meter={@token_meter}
          />
        </div>

    </section>
    """
  end

  # --- Private helpers ---

  defp selected_run([], _selected_id), do: nil

  defp selected_run(runs, selected_id) do
    Enum.find(runs, &(selected_id && &1.id == selected_id)) || List.first(runs)
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
end
