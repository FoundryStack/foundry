defmodule PhoenixLLMChat.Stores.MemorySessionStore do
  @moduledoc """
  In-memory session store using an Agent.
  Useful for tests and development where persistence is not needed.
  Implements the SessionStore behaviour.
  """

  @behaviour PhoenixLLMChat.Behaviours.SessionStore

  def start_link(opts) do
    Agent.start_link(fn -> %{} end, opts)
  end

  def load(session_id) do
    case :ets.lookup(:phoenix_llm_chat_sessions, session_id) do
      [{^session_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def save(session_id, data) do
    :ets.insert(:phoenix_llm_chat_sessions, {session_id, data})
    :ok
  end

  def list do
    case :ets.match(:phoenix_llm_chat_sessions, {:"$1", :_}) do
      [[key] | rest] -> {:ok, [key | Enum.map(rest, &List.first/1)]}
      [] -> {:ok, []}
    end
  end

  def delete(session_id) do
    :ets.delete(:phoenix_llm_chat_sessions, session_id)
    :ok
  end

  def init do
    :ets.new(:phoenix_llm_chat_sessions, [:set, :public, :named_table])
  end
end
