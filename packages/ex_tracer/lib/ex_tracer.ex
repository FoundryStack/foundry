defmodule ExTracer do
  @moduledoc """
  Generic scenario extraction primitives shared across tracing packages.

  ExTracer provides the core data structures and behaviours for walking test ASTs,
  classifying function calls into typed `Step` structs, expanding those steps through
  pluggable adapters, and assembling a coverage-annotated `Report`.

  It is the foundation for higher-level packages such as `ScenarioTracer`.

  ## Key modules

  - `ExTracer.Step` — a single meaningful call captured from a test body
  - `ExTracer.Scenario` — a group of steps extracted from a `describe`/`test` block
  - `ExTracer.Lookup` — cross-reference index linking steps to nodes and runtime traces
  - `ExTracer.Adapter` — behaviour for domain-specific call classification and expansion
  - `ExTracer.TestFramework` — behaviour for supporting different test DSLs
  - `ExTracer.TestScanner` — AST-based test file scanning
  - `ExTracer.CallTracer` — collects executed traces from a test block
  - `ExTracer.FlowSummary` — assigns IDs, attaches focus targets, summarizes coverage
  - `ExTracer.FlowExpander` — expands steps through registered adapters
  - `ExTracer.TraceCollector` — behaviour for recording runtime test outcomes
  - `ExTracer.TraceStore` — behaviour for loading and matching persisted traces
  - `ExTracer.Report` — final output with scenarios, coverage, and performance data

  ## Quick example

      alias ExTracer.{TestScanner, FlowSummary}

      scenarios =
        TestScanner.extract_from_ast(
          ast,
          MyApp.AccountsTest,
          "test/myapp/accounts_test.exs",
          alias_map,
          ScenarioTracer.TestFrameworks.ExUnit,
          fn scenario ->
            FlowSummary.assign_step_ids(scenario.flow)
          end
        )

  See the [README](https://hexdocs.pm/ex_tracer) for full usage and adapter examples.
  """
end
