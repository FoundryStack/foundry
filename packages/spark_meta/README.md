# SparkMeta

Generic Spark DSL walker and introspection library. Provides a unified way to inspect any [Spark](https://hexdocs.pm/spark)-based DSL module — extracting extensions, entities, options, and persisted state — with an opt-in handler system for richer, extension-specific output.

## Features

- Walk any Spark DSL module into a normalized `DslState` struct
- Query entities, options, and persisted values without knowing the DSL internals
- Register per-extension handlers (`SparkMeta.Extension`) for richer extraction
- Pluggable analyzer pipeline (`SparkMeta.Analyzer`) that produces a typed `Analysis` struct
- Built-in analyzers for Ash resources, AshAuthentication strategies, AshStateMachine, and module docs
- Thread-safe `Registry` backed by ETS for hot-path handler lookups
- Optional source provider for attaching source text/AST to the analysis context

## Installation

```elixir
def deps do
  [
    {:spark_meta, "~> 0.1"}
  ]
end
```

## Quick Start

```elixir
# Walk a Spark module into a raw DslState
{:ok, state} = SparkMeta.walk(MyApp.Accounts.User)

state.extensions        # => [Ash.Resource, ...]
state.sections          # => %{[:attributes] => [%Ash.Resource.Attribute{...}, ...], ...}
state.options           # => %{[:attributes] => %{allow_nil?: false, ...}, ...}
state.persisted         # => %{domain: MyApp.Domain, ...}
state.extension_data    # => %{Ash.Resource => %{attributes: [...], actions: [...], ...}}
```

## Analyzer Pipeline

`SparkMeta.analyze/2` runs a configurable pipeline of `SparkMeta.Analyzer` modules and returns a typed `Analysis` struct with extracted facts and any non-fatal diagnostics.

```elixir
{:ok, analysis} = SparkMeta.analyze(MyApp.Accounts.User)

analysis.facts[:attributes]   # => [%{name: :email, type: :string, ...}, ...]
analysis.facts[:actions]      # => [%{name: :create, type: :create, ...}, ...]
analysis.diagnostics          # => [] (list of non-fatal issue maps)
```

Run with custom analyzers:

```elixir
{:ok, analysis} = SparkMeta.analyze(MyApp.Accounts.User,
  analyzers: SparkMeta.default_analyzers() ++ [MyApp.Analyzers.Compliance]
)
```

## Implementing a Custom Analyzer

```elixir
defmodule MyApp.Analyzers.Compliance do
  @behaviour SparkMeta.Analyzer

  @impl true
  def analyze(%SparkMeta.Context{} = ctx, %SparkMeta.Analysis{} = analysis) do
    policies = SparkMeta.entities(ctx.module, [:policies])

    analysis =
      analysis
      |> SparkMeta.Analysis.put_fact(:policy_count, length(policies))
      |> SparkMeta.Analysis.put_fact(:has_policies, policies != [])

    {:ok, analysis}
  end
end
```

## Registering Extension Handlers

Register a handler for a specific Spark extension to enrich `DslState.extension_data`:

```elixir
SparkMeta.Registry.register(MyExtension, MyExtensionHandler)
```

The handler must implement `SparkMeta.Extension`:

```elixir
defmodule MyExtensionHandler do
  @behaviour SparkMeta.Extension

  @impl true
  def extract(extension_module, %SparkMeta.DslState{} = dsl_state) do
    entities = dsl_state.sections[[:my_extension]] || []
    %{items: Enum.map(entities, & &1.name)}
  end
end
```

Handlers are registered automatically at application start if they call `SparkMeta.Registry.register/2` inside an `Application.start/2` callback. The built-in `SparkMeta.Handlers.AshResource` handler is registered automatically when Ash is loaded.

## Convenience Functions

```elixir
SparkMeta.spark_module?(module)           # => true | false
SparkMeta.extensions(module)              # => [MyExt, ...]
SparkMeta.entities(module, [:attributes]) # => [%Ash.Resource.Attribute{...}, ...]
SparkMeta.get_opt(module, [:actions, :defaults], :accept, nil)
SparkMeta.get_persisted(module, :domain, nil)
```

## Source Provider

Attach source material to the analysis context for analyzers that need it:

```elixir
{:ok, analysis} = SparkMeta.analyze(MyResource,
  source_provider: SparkMeta.SourceProvider.FileSystem
)
# ctx.source_path, ctx.source_text, ctx.source_ast are populated for analyzers
```

Implement `SparkMeta.SourceProvider` to supply source from any backing store.

## Built-in Analyzers

| Module | Facts produced |
|---|---|
| `SparkMeta.Analyzers.ModuleDoc` | `:moduledoc` |
| `SparkMeta.Analyzers.Extensions` | `:extensions`, `:persisted` |
| `SparkMeta.Analyzers.AshResource` | `:attributes`, `:relationships`, `:actions`, `:policies`, `:compliance`, `:telemetry_prefix` |
| `SparkMeta.Analyzers.StateMachine` | `:states`, `:events`, `:transitions` |
| `SparkMeta.Analyzers.AuthStrategies` | `:auth_strategies` |

## License

MIT
