defmodule Foundry.Chat.Session do
  @moduledoc """
  Chat session resource backed by Mnesia disc_copies.

  Each session has a unique ID, a list of messages (role + content), and
  timestamps. Mnesia ensures persistence across restarts without requiring
  a separate database.

  ## Mnesia Setup

  The Mnesia table is created and initialized at application startup in
  `Foundry.Application.init_mnesia/0`. The table name is `:foundry_chat_sessions`.
  """

  use Ash.Resource,
    domain: Foundry.Chat,
    data_layer: Ash.DataLayer.Mnesia

  mnesia do
    table(:foundry_chat_sessions)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :session_id, :string do
      description("Unique session identifier for grouping conversations.")
      allow_nil?(false)
      public?(true)
    end

    attribute :messages, {:array, :map} do
      description(
        "Message history. Each message is a map with :role (user|assistant|system), :content, and :timestamp."
      )

      default([])
      public?(true)
    end

    attribute :session_digest, :map do
      description(
        "Compact session memory for Studio copilot runs: selected nodes, recent files, proposal ids, and condensed conclusions."
      )

      default(%{})
      public?(true)
    end

    attribute :title, :string do
      description("Human-readable session title, auto-generated from first message.")
      allow_nil?(true)
      public?(true)
    end

    attribute :model, :string do
      description("LLM model used for the session.")
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)
      accept([:session_id, :messages, :session_digest, :title, :model])
    end

    update :persist_messages do
      description("Replace the stored message history for the session.")
      accept([:messages, :session_digest])
    end

    update :add_message do
      description("Append a message to the session's message history.")
      accept([])

      change(
        after_action(fn changeset, result, _context ->
          new_message = changeset.context[:message]

          if new_message do
            updated_messages = (result.messages || []) ++ [new_message]

            Ash.Changeset.change_attribute(result, :messages, updated_messages)
          else
            {:ok, result}
          end
        end)
      )
    end
  end

  calculations do
    calculate :message_count, :integer, expr(length(messages)) do
      description("Number of messages in this session.")
    end
  end
end
