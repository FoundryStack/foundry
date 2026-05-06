defmodule ExTracer.Scenario do
  @moduledoc false

  @derive Jason.Encoder
  defstruct [
    :id,
    :name,
    :category,
    :level,
    :source_file,
    :source_module,
    :evidence_mode,
    :trace_status,
    nodes: [],
    graph_path: [],
    compliance_links: [],
    flow: [],
    evidence_summary: %{},
    tests: [],
    tags: []
  ]
end
