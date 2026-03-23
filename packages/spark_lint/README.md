# SparkLint

A minimal, zero-dependency lint rule runner for Elixir/Spark/Ash projects.

SparkLint ships **only the framework** — the behaviour, structs, and runner. Rules ship separately as Hex packages or as part of your application. This design lets you:

- Use SparkLint in projects
- Publish your own rule packages on Hex
- Compose rules from multiple independent packages
- Test rules in isolation

## Quick Start

### 1. Add to Your Project

```elixir
def deps do
  [
    {:spark_lint, "~> 0.1"}
  ]
end
```

### 2. Write a Rule

```elixir
defmodule MyApp.LintRules.MissingDoc do
  @behaviour SparkLint.Rule

  @impl SparkLint.Rule
  def check(module, _ctx) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, :none, _, _} ->
        {:ok,
         [
           %SparkLint.Violation{
             rule: :missing_moduledoc,
             module: module,
             message: "#{inspect(module)} is missing @moduledoc",
             severity: :error
           }
         ]}

      _ ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end
end
```

### 3. Run Rules

```elixir
modules = [MyApp.Resource1, MyApp.Resource2, MyApp.Reactor1]
rules = [MyApp.LintRules.MissingDoc]

{violations, errors} = SparkLint.run(rules, modules)

Enum.each(violations, fn v ->
  IO.puts("#{v.severity}: [#{v.rule}] #{inspect(v.module)}: #{v.message}")
end)
```

## API

### `SparkLint.run(rules, modules, base_context \\ %{})`

Execute a list of rules against a list of modules.

**Arguments:**

- `rules` — list of rule module atoms, each implementing `SparkLint.Rule`
- `modules` — list of compiled module atoms to lint
- `base_context` — optional map with `:metadata` key; passed to all rules

**Returns:**

`{violations, errors}` tuple:

- `violations` — sorted list of `SparkLint.Violation` structs
  - Sorted by severity (`:error` → `:warning` → `:info`)
  - Within severity, sorted alphabetically by module name
- `errors` — list of `%{rule: atom, module: atom, reason: term}` tuples for rules that returned `{:error, reason}`

**Example:**

```elixir
{violations, errors} = SparkLint.run(
  [Rule1, Rule2],
  [Module1, Module2, Module3],
  %{metadata: %{project_root: "/home/user/myapp"}}
)

if errors != [] do
  IO.puts("Runner crashed in #{length(errors)} rule(s):")
  Enum.each(errors, fn err ->
    IO.puts("  #{inspect(err.rule)}: #{inspect(err.reason)}")
  end)
end

Enum.each(violations, fn v ->
  IO.puts("[#{v.severity}] #{v.rule}: #{inspect(v.module)}")
  IO.puts("  #{v.message}")
end)
```

### `SparkLint.Rule` Behaviour

Implement this behaviour to create a lint rule.

**Callback:**

```elixir
@callback check(module :: module(), context :: SparkLint.Context.t()) ::
            {:ok, [SparkLint.Violation.t()]} | {:error, term()}
```

**Arguments:**

- `module` — a single compiled module atom being linted
- `context` — `SparkLint.Context` struct with:
  - `:module` — the current module (same as first argument)
  - `:modules` — all modules being linted (for cross-module analysis)
  - `:metadata` — opaque map passed from `SparkLint.run/3`; rules decode this as needed

**Returns:**

- `{:ok, violations}` — a (possibly empty) list of `SparkLint.Violation` structs
- `{:error, reason}` — rule crashed; reason is any term (string, exception, etc)

**Important:** Wrap any risky operations in `try/rescue` and return `{:ok, []}` on crash rather than propagating the error. The runner collects `{:error, reason}` results for visibility, but a crashed rule should not stop other rules from running.

### `SparkLint.Violation` Struct

Represents a single lint finding.

**Fields:**

- `:rule` — atom rule identifier (e.g., `:missing_doc`, `:unused_attribute`)
- `:module` — the module the violation was found in
- `:message` — human-readable description
- `:severity` — `:error` | `:warning` | `:info`
- `:step` — optional, for step-scoped violations (e.g., in Reactors)
- `:attribute` — optional, for attribute-scoped violations

**Example:**

```elixir
%SparkLint.Violation{
  rule: :missing_description,
  module: MyApp.Finance.Ledger,
  message: "Ledger.amount is missing a description",
  severity: :error,
  attribute: :amount
}
```

### `SparkLint.Context` Struct

Passed to each rule during a lint run.

**Fields:**

- `:module` — current module being checked
- `:modules` — all modules in the lint run (enables cross-module rules)
- `:metadata` — opaque application-specific data (rules decode as needed)

**Example:**

```elixir
# Inside a rule:
def check(module, ctx) do
  project_root = ctx.metadata[:project_root]
  sensitive_modules = ctx.metadata[:sensitive_modules]

  if module in sensitive_modules do
    # Check this module against stricter rules
    check_sensitive(module)
  else
    {:ok, []}
  end
end
```

## Metadata Convention

`SparkLint.run/3` accepts an optional `base_context` map. The runner extracts the `:metadata` key and passes it to each rule via `SparkLint.Context`.

**Recommended metadata keys:**

```elixir
SparkLint.run(rules, modules, %{
  metadata: %{
    project_root: "/home/user/myapp",
    manifest: parsed_manifest_keyword_list,
    sensitive_modules: [MyApp.Finance, MyApp.PII],
    custom_config: %{...}
  }
})
```

Each rule documents which metadata keys it expects. Rules should gracefully handle missing keys:

```elixir
def check(module, ctx) do
  project_root = ctx.metadata[:project_root] || File.cwd!()
  # ...
end
```

## Mix Task

SparkLint provides an optional `mix spark_lint.check` task for projects that want a standard entry point.

**Configuration:**

Add to `config/config.exs`:

```elixir
config :spark_lint, :rules, [
  MyApp.LintRules.MissingDoc,
  MyApp.LintRules.UnusedAttribute
]

config :spark_lint, :modules_fn, &MyApp.Discovery.all_modules/0
```

**Usage:**

```bash
# Run rules and print text output
mix spark_lint.check

# JSON output
mix spark_lint.check --json

# Exit codes:
#   0 — all passed (no :error violations)
#   1 — one or more :error violations found
#   2 — runner crashed
```

**When not configured:**

The task prints a help message and exits 0:

```
spark_lint: no rules configured.

To use spark_lint.check, add to your config/config.exs:

    config :spark_lint, :rules, [MyApp.LintRules.MyRule]
    config :spark_lint, :modules_fn, &MyApp.Discovery.all_modules/0

Rules must implement the SparkLint.Rule behaviour.
```

## Writing Rules

### Good Rule Structure

```elixir
defmodule MyApp.LintRules.MyRule do
  @moduledoc """
  Checks that all Ash resources have a :sensitive attribute if in sensitive_modules.

  Uses metadata:
    - `:sensitive_modules` — list of module atoms that require extra scrutiny
  """

  @behaviour SparkLint.Rule

  @impl SparkLint.Rule
  def check(module, ctx) do
    sensitive = ctx.metadata[:sensitive_modules] || []

    if module not in sensitive do
      {:ok, []}
    else
      check_sensitive(module)
    end
  rescue
    _ ->
      # Graceful degradation: if we can't check this module, don't fail the whole run
      {:ok, []}
  end

  defp check_sensitive(module) do
    try do
      attributes = Ash.Resource.Info.attributes(module)

      violations =
        if Enum.any?(attributes, &(&1.name == :sensitive)) do
          []
        else
          [
            %SparkLint.Violation{
              rule: :missing_sensitive_flag,
              module: module,
              message: "#{inspect(module)} is sensitive but missing :sensitive attribute",
              severity: :error
            }
          ]
        end

      {:ok, violations}
    rescue
      _ -> {:ok, []}
    end
  end
end
```

### Common Patterns

**Cross-module analysis:**

```elixir
def check(module, ctx) do
  # Use ctx.modules to reference other modules being linted
  referenced = find_references(module, ctx.modules)
  # ...
end
```

**File system checks:**

```elixir
def check(module, ctx) do
  project_root = ctx.metadata[:project_root] || File.cwd!()
  # Safe file access using the project root
  # ...
end
```

**Reading project metadata:**

```elixir
def check(module, ctx) do
  manifest = ctx.metadata[:manifest] || []
  domain_type = Keyword.get(manifest, :domain_type, :other)
  # ...
end
```

## Design Principles

### Zero Dependencies

SparkLint intentionally has zero required dependencies. This keeps the package lightweight and avoids pulling in heavy transitive deps. Rules that need Spark, Ash, or other libraries can declare them as dependencies—SparkLint doesn't assume what rules need.

### Pure Computation

The runner is stateless. No GenServer, no supervision, no side effects. Call `SparkLint.run/3` anywhere: in mix tasks, tests, or application code.

### Framework Only

SparkLint defines the contract (behaviour + structs) and the executor (runner). Rules ship separately. This prevents tight coupling and lets teams publish independent rule packages.

### Graceful Degradation

Rules that crash return `{:error, reason}`, but the runner continues. Violations are collected and returned for inspection. This lets CI pipelines fail gracefully on rule errors without blocking the entire lint run.

## Comparison to Other Linters

| Feature | SparkLint | Credo | Elixir Compiler |
|---|---|---|---|
| **Rules** | Custom behaviour | Built-in + plugins | Language-level checks |
| **Dependencies** | Zero | Yes (many) | Part of runtime |
| **Domain** | Application-specific | Code style | Syntax/types |
| **Extensible** | Yes (via Rule behaviour) | Yes (via plugins) | Limited (via warnings) |

SparkLint is best for:

- Enforcing **project-specific invariants** (sensitive resources, audit trails, idempotency)
- Composing rules from **multiple independent packages**
- Linting **Ash resources, Reactors, or custom DSLs** (via Spark introspection)
- **Minimal, zero-dependency** linting in production codebases

## Examples

See [the Foundry repository](https://github.com/anthropics/foundry) for real-world rule implementations:

- `Foundry.LintRules.PaperTrailRule` — sensitive resources must use AshPaperTrail
- `Foundry.LintRules.DescriptionRule` — resources and attributes must have docs
- `Foundry.LintRules.IdempotencyRule` — reactors with side effects need idempotency keys
- `Foundry.LintRules.RunbookRule` — complex reactors need runbooks

## Publishing Rules

To publish your rules as a Hex package:

1. Create a new Mix project: `mix new my_lint_rules`
2. Add `:spark_lint` as a dependency
3. Implement rules in `lib/my_lint_rules/*.ex`, each implementing `SparkLint.Rule`
4. Document metadata expectations
5. Publish to Hex: `mix hex.publish`

Users of your package add it to their `mix.exs` and configure rules in their `config/config.exs`.

## License

SparkLint is part of the Foundry project and uses the same license.
