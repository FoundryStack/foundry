defmodule Foundry.Context.SessionState do
  @moduledoc """
  Captures system map state at the start of an editing session.
  Used by the studio to render preview mode during active proposals.

  Delta computation is deferred to Phase 4+.
  graph_delta is always nil in Phase 1.
  """

  @enforce_keys [:session_id, :captured_at]
  defstruct [
    :session_id,
    :captured_at,
    node_ids: [],
    edge_hashes: []
  ]

  @spec init_table :: atom()
  def init_table do
    :ets.new(:foundry_session_state, [:named_table, :public, read_concurrency: true])
  end

  @spec delta(String.t(), map()) :: nil
  def delta(_session_id, _current_context) do
    nil
  end
end
