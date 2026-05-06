defmodule ExTracer.PerformanceReport do
  @moduledoc false

  defstruct total_test_duration_ms: 0,
            slowest_tests: [],
            fastest_tests: [],
            avg_duration_ms: 0.0,
            extraction_duration_ms: 0
end
