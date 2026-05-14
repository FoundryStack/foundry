# ScenarioTracer

Ready-to-use ExUnit and JSON-backed scenario tracing built on top of [ExTracer](../ex_tracer/README.md). ScenarioTracer wires together AST scanning, runtime trace collection, and report generation into a single Mix task abstraction — so you can extract living documentation from your existing test suite with minimal configuration.

## Features

- ExUnit formatter that captures test outcomes and durations at runtime
- JSON file-based trace collector and trace store (no external services required)
- `MixTask` behaviour for building project-specific trace extraction pipelines
- Built-in support for ExUnit and StreamData test blocks
- Produces `ExTracer.Report` structs ready for further processing or export

## Installation

```elixir
def deps do
  [
    {:scenario_tracer, "~> 0.1"},
    {:jason, "~> 1.4"}
  ]
end
```

## Quick Start

### 1. Record runtime traces

Add `ScenarioTracer.ExUnitFormatter` to your ExUnit configuration so test outcomes are captured to disk:

```elixir
# test/test_helper.exs
ExUnit.start()

ExUnit.configure(
  formatters: [ExUnit.CLIFormatter, ScenarioTracer.ExUnitFormatter],
  # Pass trace_dir via ExUnit opts or application config
  trace_dir: Path.join(File.cwd!(), "traces")
)
```

Or start the formatter manually with options:

```elixir
{:ok, _pid} = ScenarioTracer.ExUnitFormatter.start_link(trace_dir: "traces/")
```

After `mix test`, a JSON file per test suite will appear in `traces/`.

### 2. Define a Mix task

Implement `ScenarioTracer.MixTask` to describe how your project's sources should be wired:

```elixir
defmodule Mix.Tasks.Scenarios.Extract do
  use Mix.Task
  @behaviour ScenarioTracer.MixTask

  @impl ScenarioTracer.MixTask
  def project_root, do: File.cwd!()

  @impl ScenarioTracer.MixTask
  def adapters, do: [MyApp.Tracer.ResourceAdapter]

  @impl ScenarioTracer.MixTask
  def frameworks, do: [ScenarioTracer.TestFrameworks.ExUnit]

  @impl ScenarioTracer.MixTask
  def trace_dir(root), do: Path.join(root, "traces")

  @impl ScenarioTracer.MixTask
  def node_source(root) do
    # Return a list of maps describing your application nodes
    MyApp.Tracer.NodeBuilder.build(root)
  end

  @impl ScenarioTracer.MixTask
  def lookup_builder(root, nodes, runtime) do
    %ExTracer.Lookup{
      by_id:   Map.new(nodes, &{&1.id, &1}),
      aliases: MyApp.Tracer.AliasMap.build(root),
      code:    MyApp.Tracer.CodeIndex.build(nodes),
      runtime: runtime
    }
  end

  @impl Mix.Task
  def run(_args) do
    report = ScenarioTracer.MixTask.run(__MODULE__)
    IO.puts("Extracted #{length(report.scenarios)} scenarios")
    IO.puts("Coverage: #{report.coverage.coverage_pct}%")
  end
end
```

Run with:

```shell
mix scenarios.extract
```

## Behaviours

### `ScenarioTracer.MixTask`

| Callback | Returns | Purpose |
|---|---|---|
| `project_root/0` | `String.t()` | Absolute path to project root |
| `adapters/0` | `[module()]` | `ExTracer.Adapter` implementations |
| `frameworks/0` | `[module()]` | `ExTracer.TestFramework` implementations |
| `trace_dir/1` | `String.t()` | Directory containing JSON trace files |
| `node_source/1` | `[map()]` | Application node descriptors |
| `lookup_builder/3` | `ExTracer.Lookup.t()` | Builds the cross-reference index |

### `ScenarioTracer.ExUnitFormatter`

A GenServer that hooks into ExUnit's event stream. Handles:

- `:suite_started` — initializes trace collection state
- `:test_started` — records test start time
- `:test_finished` — records outcome, duration, and any failure message

### `ScenarioTracer.TraceCollector.JsonFile`

Implements `ExTracer.TraceCollector`. Writes one JSON file per test module to `trace_dir`. Each file contains an array of event maps:

```json
[
  {
    "scenario_id": "myapp-accounts-user-creates-a-user",
    "test_name": "creates a user with valid params",
    "outcome": "passed",
    "duration_ms": 42,
    "captured_at": "2026-05-06T10:00:00Z"
  }
]
```

### `ScenarioTracer.TraceStore.JsonFile`

Implements `ExTracer.TraceStore`. Loads all JSON files from `trace_dir` and indexes them by scenario ID. Provides fuzzy test-name matching to handle minor formatting differences between compile-time and runtime names.

## Built-in Test Frameworks

| Module | Recognized macros |
|---|---|
| `ScenarioTracer.TestFrameworks.ExUnit` | `test/2`, `test/3` |
| `ScenarioTracer.TestFrameworks.StreamData` | `property/2`, `property/3` |

## License

MIT
