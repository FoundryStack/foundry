defmodule FoundryWeb.ChatInputComponents do
  @moduledoc false
  use FoundryWeb, :html

  alias FoundryWeb.ChatTokenMeter
  alias FoundryWeb.ChatModelCatalog

  attr :input, :string, default: ""
  attr :chat_loading, :boolean, required: true
  attr :selected_model, :map, default: nil
  attr :model_catalog, :list, default: []
  attr :session_digest, :map, default: %{}
  attr :token_meter, :map, required: true

  def chat_input_form(assigns) do
    grouped_catalog = family_groups(assigns.model_catalog)

    active_proposal_id = assigns.session_digest["active_proposal_id"]
    active_proposal_status = assigns.session_digest["active_proposal_status"]

    show_proposal_actions =
      is_binary(active_proposal_id) and
        active_proposal_status not in ["applied", "cancelled"]

    assigns =
      assigns
      |> assign(:grouped_catalog, grouped_catalog)
      |> assign(:active_proposal_id, active_proposal_id)
      |> assign(:show_proposal_actions, show_proposal_actions)

    ~H"""
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
          phx-change="update_chat_input"
          phx-debounce="100"
          class="w-full resize-none rounded-[18px] border border-white/10 bg-transparent px-3 py-3 text-sm leading-6 text-base-content outline-none backdrop-blur-sm placeholder:text-neutral-content/50"
        ><%= @input %></textarea>
        <%= if @show_proposal_actions do %>
          <div class="mt-2 flex items-center gap-2">
            <p class="text-[10px] font-semibold uppercase tracking-[0.12em] text-neutral-content">
              Active proposal:
            </p>
            <button
              type="button"
              phx-click="proposal_apply"
              phx-value-id={@active_proposal_id}
              disabled={@chat_loading}
              class="rounded-selector bg-success/90 px-2.5 py-1.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-base-100 transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Apply
            </button>
            <button
              type="button"
              phx-click="proposal_revise"
              phx-value-id={@active_proposal_id}
              disabled={@chat_loading}
              class="rounded-selector border border-warning/30 bg-warning/10 px-2.5 py-1.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-warning transition-colors hover:bg-warning/15 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Revise
            </button>
            <button
              type="button"
              phx-click="proposal_cancel"
              phx-value-id={@active_proposal_id}
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
                <optgroup :for={{family_label, entries} <- @grouped_catalog} label={family_label}>
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
    """
  end

  # --- Private helpers ---

  defp family_groups(catalog), do: ChatModelCatalog.family_groups(catalog)
end
