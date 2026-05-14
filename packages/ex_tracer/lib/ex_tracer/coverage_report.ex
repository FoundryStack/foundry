defmodule ExTracer.CoverageReport do
  @moduledoc false

  defstruct total_nodes: 0,
            covered_nodes: 0,
            coverage_pct: 0.0,
            uncovered_node_ids: [],
            coverage_by_type: %{},
            delta: nil
end
