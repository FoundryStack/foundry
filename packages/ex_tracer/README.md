# ExTracer

Generic scenario extraction primitives for Elixir test suites. ExTracer provides the core data structures and behaviours for walking test ASTs, classifying function calls into typed steps, expanding those steps through pluggable adapters, and assembling a coverage-annotated report.

It is the foundation for higher-level packages such as [ScenarioTracer](../scenario_tracer/README.md).

## Features

- Scan ExUnit test files via AST analysis into typed `Scenario` and `Step` structs
- Pluggable `Adapter` behaviour for domain-specific call classification and step expansion
- `TestFramework` behaviour for supporting ExUnit, StreamData, or custom test DSLs
- `Lookup` index for cross-referencing steps against nodes and runtime traces
- `TraceCollector` / `TraceStore` behaviours for persisting and loading runtime traces
- `FlowSummary`, `FlowHints`, and `FlowExpander` for annotating and enriching step flows
- Coverage and performance reporting via `CoverageReport` and `PerformanceReport`

## Installation

```elixir
def deps do
  [
    {:ex_tracer, "~> 0.1"}
  ]
end
```

## Core Concepts

### Steps

A `Step` represents a single meaningful call captured from a test body:

```
%ExTracer.Step{
  id:                 "step-001",
  type:               :call,
  kind:               :action,
  label:              "create user",
  node_id:            "MyApp.Accounts.User",
  focus_node_id:      "MyApp.Accounts.User",
  focus_targets:      [],
  emits:              [],
  action:             :create,
  actor:              nil,
  status:             :passed,
  module_function:    {MyApp.Accounts.User, :create},
  source_snippet:     "User.create!(params)",
  result:             "user",
  line:               42,
  test_name:          "creates a user with valid params",
  assertion_context:  %{result: "user", status: :passed}
}
```

### Scenarios

A `Scenario` groups a set of steps extracted from a single `describe` / `test` block:

```
%ExTracer.Scenario{
  id:            "myapp-accounts-user-create-user-with-valid-params",
  name:          "creates a user with valid params",
  category:      "accounts",
  source_file:   "test/myapp/accounts/user_test.exs",
  flow:          [%ExTracer.Step{...}, ...],
  nodes:         ["MyApp.Accounts.User", ...],
  graph_path:    ["MyApp.Accounts.User"],
  tests:         [%{name: "...", outcome: :passed, duration_ms: 12}],
  tags:          [:smoke]
}
```

### Lookup

The `Lookup` index is the glue between extracted steps and runtime traces:

```elixir
lookup = %ExTracer.Lookup{
  by_id:   %{"MyApp.Accounts.User" => node_map},
  aliases: %{User: MyApp.Accounts.User},
  code:    %{"MyApp.Accounts.User" => %{kind: :ash_resource, ...}},
  runtime: %{"creates a user..." => [%ExTracer.RuntimeTrace{...}]}
}
```

## Implementing an Adapter

Adapters classify AST calls into steps and optionally expand steps into sub-steps:

```elixir
defmodule MyApp.Tracer.ResourceAdapter do
  @behaviour ExTracer.Adapter

  @impl true
  def classify_call(module_ast, fun, args, alias_map, lookup, _opts) do
    with {:ok, node_id} <- resolve_node(module_ast, alias_map, lookup),
         true <- fun in [:create!, :update!, :destroy!] do
      %ExTracer.Step{
        type:    :call,
        kind:    :action,
        label:   "#{fun} #{node_label(node_id)}",
        node_id: node_id,
        action:  fun
      }
    else
      _ -> nil
    end
  end

  @impl true
  def expand_step(%ExTracer.Step{kind: :action} = step, lookup) do
    # Return sub-steps (e.g. validation, persistence)
    [step]
  end

  defp resolve_node(module_ast, alias_map, lookup), do: ...
  defp node_label(node_id), do: ...
end
```

## Scanning Test Files

```elixir
alias ExTracer.{TestScanner, Lookup}

scenarios =
  TestScanner.extract_from_ast(
    ast,
    MyApp.AccountsTest,
    "test/myapp/accounts_test.exs",
    alias_map,
    ScenarioTracer.TestFrameworks.ExUnit,
    fn scenario ->
      ExTracer.FlowSummary.assign_step_ids(scenario.flow)
    end
  )
```

## Flow Utilities

```elixir
# Assign sequential IDs to steps
steps = ExTracer.FlowSummary.assign_step_ids(steps)

# Attach focus_targets so UI can highlight related nodes
steps = ExTracer.FlowSummary.attach_focus_targets(steps)

# Summarize coverage
summary = ExTracer.FlowSummary.summarize_evidence(steps)
# => %{executed_steps: 5, passed_steps: 5, failed_steps: 0, ...}

# Derive which nodes and graph paths a flow covers
{nodes, graph_path} = ExTracer.FlowSummary.derive_flow_summaries(steps)
```

## Runtime Traces

Implement `ExTracer.TraceCollector` to record test outcomes at runtime:

```elixir
defmodule MyTraceCollector do
  @behaviour ExTracer.TraceCollector

  @impl true
  def start(opts), do: {:ok, %{dir: opts.trace_dir, events: []}}

  @impl true
  def record(state, event), do: %{state | events: [event | state.events]}

  @impl true
  def flush(%{dir: dir, events: events}) do
    File.write!(Path.join(dir, "trace.json"), Jason.encode!(events))
    :ok
  end
end
```

Implement `ExTracer.TraceStore` to load recorded traces and match them to scenarios:

```elixir
defmodule MyTraceStore do
  @behaviour ExTracer.TraceStore

  @impl true
  def load(%{trace_dir: dir}) do
    # Return %{scenario_id => [RuntimeTrace.t()]}
  end

  @impl true
  def match(%ExTracer.RuntimeTrace{test_name: name}, test_name), do: name == test_name
end
```

## Report Structure

```elixir
%ExTracer.Report{
  extracted_at:  ~U[2026-05-06 10:00:00Z],
  duration_ms:   1234,
  scenarios:     [%ExTracer.Scenario{...}, ...],
  coverage:      %ExTracer.CoverageReport{
    total_nodes:      42,
    covered_nodes:    38,
    coverage_pct:     90.5,
    uncovered_node_ids: [...]
  },
  performance:   %ExTracer.PerformanceReport{
    total_test_duration_ms: 5600,
    avg_duration_ms:        112,
    slowest_tests:          [...],
    fastest_tests:          [...]
  },
  node_index:    %{},
  warnings:      []
}
```

## License

MIT
