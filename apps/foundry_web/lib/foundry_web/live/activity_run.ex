defmodule FoundryWeb.ActivityRun do
  @moduledoc """
  Structured representation of an LLM activity run with tracing.

  Tracks a single LLM request including streaming state, tool execution, tokens, and trace events.
  """

  @enforce_keys [:id, :request_ref, :started_at, :status, :provider]
  defstruct [
    :id,
    :request_ref,
    :started_at,
    :finished_at,
    :status,
    :provider,
    :diagnostics,
    :mode,
    :proposal,
    :user_message,
    :response,
    :response_preview,
    :error,
    :metadata,
    :token_usage,
    :total_tokens,
    stream_cursor: 0,
    events: [],
    grouped_events: [],
    phase_groups: [],
    phase_counts: %{},
    provenance: %{},
    event_count: 0,
    grouped_event_count: 0,
    tool_count: 0,
    file_count: 0,
    tools: [],
    files: [],
    read_files: [],
    written_files: []
  ]

  # Allow get_in/put_in/update_in on ActivityRun structs (used in templates).
  defdelegate fetch(run, key), to: Map
  defdelegate get(run, key, default), to: Map
  defdelegate get_and_update(run, key, fun), to: Map
  defdelegate pop(run, key), to: Map

  @doc """
  Creates a new activity run with the given attributes.
  """
  def new(attrs) do
    struct!(__MODULE__, attrs)
  end

  @doc """
  Converts the activity run to a plain map for serialization.
  """
  def to_map(%__MODULE__{} = run) do
    run |> Map.from_struct() |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  @doc """
  Creates an activity run from a map (e.g., from persisted JSON).
  """
  def from_map(map) when is_map(map) do
    struct(__MODULE__, map)
  end
end
