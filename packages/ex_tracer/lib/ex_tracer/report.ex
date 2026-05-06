defmodule ExTracer.Report do
  @moduledoc false

  defstruct [
    :extracted_at,
    :duration_ms,
    scenarios: [],
    coverage: %{},
    performance: %{},
    node_index: %{},
    warnings: []
  ]
end
