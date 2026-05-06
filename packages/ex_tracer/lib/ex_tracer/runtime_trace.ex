defmodule ExTracer.RuntimeTrace do
  @moduledoc false

  @type t :: %__MODULE__{
          scenario_id: String.t() | nil,
          source_module: String.t() | nil,
          describe_name: String.t() | nil,
          test_name: String.t() | nil,
          file: String.t() | nil,
          line: pos_integer() | nil,
          captured_at: String.t() | nil,
          events: [map()],
          outcome: String.t() | nil,
          duration_ms: integer() | nil,
          failure_message: String.t() | nil,
          failure_line: pos_integer() | nil
        }

  defstruct [
    :scenario_id,
    :source_module,
    :describe_name,
    :test_name,
    :file,
    :line,
    :captured_at,
    :outcome,
    :duration_ms,
    :failure_message,
    :failure_line,
    events: []
  ]

  def from_map(payload) when is_map(payload) do
    struct(__MODULE__, %{
      scenario_id: payload["scenario_id"] || payload[:scenario_id],
      source_module: payload["source_module"] || payload[:source_module],
      describe_name: payload["describe_name"] || payload[:describe_name],
      test_name: payload["test_name"] || payload[:test_name],
      file: payload["file"] || payload[:file],
      line: payload["line"] || payload[:line],
      captured_at: payload["captured_at"] || payload[:captured_at],
      outcome: payload["outcome"] || payload[:outcome],
      duration_ms: payload["duration_ms"] || payload[:duration_ms],
      failure_message: payload["failure_message"] || payload[:failure_message],
      failure_line: payload["failure_line"] || payload[:failure_line],
      events: payload["events"] || payload[:events] || []
    })
  end
end
