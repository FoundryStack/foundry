# SparkLint Documentation Index

Welcome to SparkLint! This document guides you through our documentation based on what you're trying to do.

## I want to...

### Get Started (15 min)

1. Read **[README.md](./README.md)** — overview, quick start, and API summary
2. Check **[QUICK_REFERENCE.md](./QUICK_REFERENCE.md)** — copy-paste templates and cheat sheet

### Build a Lint Rule (1 hour)

1. Read **[GUIDE.md](./GUIDE.md)** — full walkthrough with examples
2. Look at **real-world examples** in [Foundry](https://github.com/anthropics/foundry/tree/main/apps/foundry/lib/foundry/lint_rules)
3. Follow patterns from **[QUICK_REFERENCE.md](./QUICK_REFERENCE.md)**

### Test My Rule

Check the **Testing Rules** section in [GUIDE.md](./GUIDE.md).

Example test structure:

```elixir
defmodule MyRuleTest do
  use ExUnit.Case
  alias SparkLint.Context

  test "finds violations" do
    ctx = %Context{module: String, modules: [String], metadata: %{}}
    {:ok, violations} = MyRule.check(String, ctx)
    assert Enum.any?(violations, &(&1.rule == :my_rule))
  end
end
```

### Publish a Rule Package to Hex

1. Read **[HEXDOCS.md](./HEXDOCS.md)** — publishing workflow
2. Follow **[CONTRIBUTING.md](./CONTRIBUTING.md)** — development setup and standards

### Contribute to SparkLint

1. Read **[CONTRIBUTING.md](./CONTRIBUTING.md)** — setup, standards, and PR process
2. Understand **[CHANGELOG.md](./CHANGELOG.md)** — versioning and release notes

### Understand the Design

Read **README.md** section "Design Principles" for:

- Why SparkLint is zero-dependency
- Why rules ship separately
- Why error handling is graceful

## Documentation Structure

| Document | Purpose | Audience | Length |
|---|---|---|---|
| [README.md](./README.md) | Overview, quick start, API | Everyone | 15 min |
| [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) | Cheat sheet, copy-paste templates | Rule authors | 5 min |
| [GUIDE.md](./GUIDE.md) | Detailed patterns and examples | Rule authors | 30 min |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Development, testing, publishing | Contributors | 15 min |
| [HEXDOCS.md](./HEXDOCS.md) | Hex publishing workflow | Package authors | 10 min |
| [CHANGELOG.md](./CHANGELOG.md) | Version history | Everyone | 5 min |
| [DOCS.md](./DOCS.md) | This file — navigation guide | Everyone | 5 min |

## API Quick Links

### Core Types

- **`SparkLint.Rule`** — behaviour all rules implement
  - Callback: `check(module(), context()) → {:ok, violations()} | {:error, reason()}`
- **`SparkLint.Violation`** — a single lint finding
  - Fields: `rule`, `module`, `message`, `severity`, `step?`, `attribute?`
- **`SparkLint.Context`** — passed to each rule
  - Fields: `module`, `modules`, `metadata`

### Functions

- **`SparkLint.run(rules, modules, base_context \\ %{})`** — execute all rules
  - Returns: `{violations, errors}`
  - Violations are sorted by severity, then module name

- **`mix spark_lint.check`** — Mix task
  - Reads rules from app config
  - Exits 0 (pass), 1 (violations), 2 (crash)

## Example Workflows

### Workflow 1: Build Your First Rule (20 min)

```
1. Read README.md (5 min)
   ↓
2. Open QUICK_REFERENCE.md (1 min)
   ↓
3. Copy template from "Implement a Rule" (1 min)
   ↓
4. Implement your check logic (5 min)
   ↓
5. Write a simple test using "Test a Rule" template (5 min)
   ↓
6. Run: mix test
```

### Workflow 2: Publish to Hex (30 min)

```
1. Read GUIDE.md thoroughly (20 min)
   ↓
2. Create project: mix new my_lint_rules
   ↓
3. Add to mix.exs: {:spark_lint, "~> 0.1"}
   ↓
4. Implement rules (following GUIDE.md patterns) (30 min)
   ↓
5. Read HEXDOCS.md (10 min)
   ↓
6. Publish: mix hex.publish
```

### Workflow 3: Contribute to SparkLint (varies)

```
1. Read CONTRIBUTING.md (10 min)
   ↓
2. Set up: git clone, mix deps.get, mix test (5 min)
   ↓
3. Make your changes (varies)
   ↓
4. Run: mix format, mix test (2 min)
   ↓
5. Submit PR with clear description (5 min)
```

## Common Questions

**Q: Where do I put my rules?**

A: In your app: `lib/my_app/lint_rules/*.ex`. Each file is a module implementing `SparkLint.Rule`.

**Q: How do I test my rules?**

A: Use ExUnit. Create a `test/my_app/lint_rules/*.ex` file, create a `SparkLint.Context` struct, and call `MyRule.check(module, context)`. See the "Testing Rules" section in [GUIDE.md](./GUIDE.md).

**Q: Can I share my rules as a Hex package?**

A: Yes! Read [HEXDOCS.md](./HEXDOCS.md) for publishing instructions.

**Q: What if my rule needs dependencies (Ash, Spark, etc.)?**

A: That's fine. SparkLint core has zero deps, but your rule package can depend on whatever you need. Users install both SparkLint and your rules.

**Q: How do I run rules in CI?**

A: Use `mix spark_lint.check` or call `SparkLint.run/3` directly from a Mix task. See [README.md](./README.md) section "Mix Task".

**Q: What if a rule crashes?**

A: The runner catches it and returns `{:error, reason}` in the errors list. Other rules continue. Best practice: wrap risky code in `try/rescue` and return `{:ok, []}` on crash.

**Q: Can rules depend on each other?**

A: Rules are independent modules, so they don't have dependencies on each other. However, they can share metadata and analysis results via the context.

**Q: How do I pass configuration to rules?**

A: Via the `metadata` field in `base_context`:

```elixir
SparkLint.run(rules, modules, %{
  metadata: %{
    my_config: "value"
  }
})
```

And in your rule:

```elixir
def check(module, ctx) do
  config = ctx.metadata[:my_config]
  # ...
end
```

## Links

- **GitHub:** https://github.com/anthropics/foundry
- **Hex:** https://hex.pm/packages/spark_lint
- **Docs:** https://hexdocs.pm/spark_lint
- **Issues:** https://github.com/anthropics/foundry/issues

## Troubleshooting

### My rule crashes on certain modules

Wrap risky code in `try/rescue`:

```elixir
def check(module, _ctx) do
  try do
    # Risky introspection
    {:ok, check_module(module)}
  rescue
    _ -> {:ok, []}
  end
end
```

### Rules aren't running

Check:

1. Rules are registered in your app's config
2. Rules implement `@behaviour SparkLint.Rule`
3. Rules return `{:ok, [violations]}` or `{:error, reason}`

### Metadata isn't available in my rule

Rules receive metadata opaquely. Make sure:

1. You're passing `%{metadata: %{...}}` to `SparkLint.run/3`
2. You're accessing it as `ctx.metadata[:key]` in your rule
3. You have a fallback: `ctx.metadata[:key] || default_value`

## Version Info

- **Current Version:** 0.1.0
- **Requires:** Elixir ~> 1.15
- **License:** Same as Foundry

See [CHANGELOG.md](./CHANGELOG.md) for release history.

---

**Have questions?** Open an issue at https://github.com/anthropics/foundry/issues
