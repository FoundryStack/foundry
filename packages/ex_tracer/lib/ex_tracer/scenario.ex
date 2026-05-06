defmodule ExTracer.Scenario do
  @moduledoc """
  A group of related steps extracted from a `describe`/`test` block.

  Scenarios bundle test-level metadata (name, source location, category) with a
  flow of steps that were executed. They carry coverage links to graph nodes,
  compliance requirements, and evidence summaries for audit purposes.

  Created by `ExTracer.TestScanner` during AST analysis and enriched by
  `ExTracer.FlowSummary`, `ExTracer.FlowExpander`, and runtime trace matching.
  """

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
