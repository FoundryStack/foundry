# SparkLint Quick Reference

## 1. Implement a Rule (5 min)

```elixir
defmodule MyApp.LintRules.MyRule do
  @behaviour SparkLint.Rule

  @impl SparkLint.Rule
  def check(module, ctx) do
    try do
      violations = []

      # Check something
      if needs_fix?(module) do
        violations = [
          %SparkLint.Violation{
            rule: :my_rule_id,
            module: module,
            message: "Fix this",
            severity: :error
          }
          | violations
        ]
      end

      {:ok, violations}
    rescue
      _ -> {:ok, []}
    end
  end

  defp needs_fix?(module) do
    # Your logic here
    false
  end
end
```

## 2. Run Rules (2 min)

```elixir
{violations, errors} = SparkLint.run(
  [MyApp.LintRules.MyRule],
  [MyApp.Resource1, MyApp.Resource2],
  %{metadata: %{key: value}}
)

Enum.each(violations, fn v ->
  IO.puts("[#{v.severity}] #{v.rule}: #{inspect(v.module)}")
  IO.puts("  #{v.message}")
end)
```

## 3. Test a Rule (3 min)

```elixir
defmodule MyApp.LintRules.MyRuleTest do
  use ExUnit.Case
  alias MyApp.LintRules.MyRule
  alias SparkLint.Context

  test "finds violations" do
    ctx = %Context{module: String, modules: [String], metadata: %{}}
    {:ok, violations} = MyRule.check(String, ctx)
    assert length(violations) >= 0
  end
end
```

## 4. Use Mix Task (1 min)

**Config:**

```elixir
# config/config.exs
config :spark_lint, :rules, [MyApp.LintRules.MyRule]
config :spark_lint, :modules_fn, &MyApp.Discovery.all_modules/0
```

**Run:**

```bash
mix spark_lint.check
mix spark_lint.check --json
```

## API Cheat Sheet

### `SparkLint.run(rules, modules, base_context \\ %{})`

Returns: `{violations, errors}`

- `violations` — list of `SparkLint.Violation` (sorted by severity, then module name)
- `errors` — list of `%{rule: atom, module: atom, reason: term}`

### `SparkLint.Rule` Behaviour

```elixir
@callback check(module(), SparkLint.Context.t()) ::
            {:ok, [SparkLint.Violation.t()]} | {:error, term()}
```

### `SparkLint.Violation` Struct

```elixir
%SparkLint.Violation{
  rule: :atom,              # required
  module: Module,           # required
  message: "string",        # required
  severity: :error,         # required (:error | :warning | :info)
  step: nil,                # optional
  attribute: nil            # optional
}
```

### `SparkLint.Context` Struct

```elixir
%SparkLint.Context{
  module: Module,           # current module being checked
  modules: [Module],        # all modules in the run
  metadata: %{}             # app-specific data (opaque to framework)
}
```

## Common Patterns

### Check Sensitive Modules Only

```elixir
def check(module, ctx) do
  sensitive = ctx.metadata[:sensitive_modules] || []
  if module in sensitive do
    check_sensitive(module)
  else
    {:ok, []}
  end
end
```

### Use Project Root

```elixir
def check(module, ctx) do
  project_root = ctx.metadata[:project_root] || File.cwd!()
  # Use project_root to read files, check paths, etc.
end
```

### Safe Introspection

```elixir
def check(module, _ctx) do
  try do
    # Introspect module (may fail if not a Resource, etc.)
    info = Ash.Resource.Info.attributes(module)
    {:ok, check_attributes(info)}
  rescue
    _ -> {:ok, []}
  end
end
```

### Multiple Violations Per Module

```elixir
def check(module, _ctx) do
  violations =
    Enum.flat_map(fields(module), fn field ->
      if bad?(field) do
        [%SparkLint.Violation{
          rule: :field_issue,
          module: module,
          message: "Field #{field.name} has issue",
          severity: :warning,
          attribute: field.name
        }]
      else
        []
      end
    end)

  {:ok, violations}
rescue
  _ -> {:ok, []}
end
```

## Severity Levels

| Severity | Blocks CI? | Use When |
|---|---|---|
| `:error` | Yes | Must be fixed before merge |
| `:warning` | No | Should be reviewed; can ship with approval |
| `:info` | No | Informational; never blocks |

## Exit Codes

When using `mix spark_lint.check`:

- **0** — ✅ All passed (no `:error` violations)
- **1** — ❌ Violations found (has `:error`)
- **2** — 💥 Runner crashed

## Tips

1. **Always graceful degrade** — wrap risky code in `try/rescue`, return `{:ok, []}`
2. **Document metadata** — add `@moduledoc` explaining which `:metadata` keys your rule uses
3. **Test edge cases** — test with built-in modules, missing extensions, etc.
4. **Keep violations focused** — one violation per issue, not one per module
5. **Use custom metadata** — pass app-specific context via the metadata map

## Links

- **Docs**: https://hexdocs.pm/spark_lint
- **Repo**: https://github.com/anthropics/foundry
- **Issues**: https://github.com/anthropics/foundry/issues
- **Hex**: https://hex.pm/packages/spark_lint

## Examples

Real-world rules from Foundry:

- `Foundry.LintRules.PaperTrailRule` — sensitive resources must use AshPaperTrail
- `Foundry.LintRules.DescriptionRule` — resources and attributes must have docs
- `Foundry.LintRules.IdempotencyRule` — reactors with side effects need idempotency keys
- `Foundry.LintRules.RunbookRule` — complex reactors need runbooks

See [Foundry repo](https://github.com/anthropics/foundry/tree/main/apps/foundry/lib/foundry/lint_rules) for implementations.
