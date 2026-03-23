# SparkLint Implementation Guide

This guide walks through building and testing lint rules for SparkLint.

## Table of Contents

1. [Creating Your First Rule](#creating-your-first-rule)
2. [Rule Anatomy](#rule-anatomy)
3. [Testing Rules](#testing-rules)
4. [Error Handling](#error-handling)
5. [Using Metadata](#using-metadata)
6. [Advanced Patterns](#advanced-patterns)

---

## Creating Your First Rule

Let's build a simple rule that checks all modules have `@moduledoc`.

### Step 1: Create the Module

```elixir
# lib/my_app/lint_rules/moduledoc_rule.ex

defmodule MyApp.LintRules.ModuledocRule do
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

      {:docs_v1, _, _, _, :hidden, _, _} ->
        # @moduledoc false is acceptable
        {:ok, []}

      _ ->
        {:ok, []}
    end
  rescue
    _ ->
      # If we can't fetch docs, assume the module is fine
      {:ok, []}
  end
end
```

### Step 2: Run It

```elixir
modules = [MyApp.Resource, MyApp.Reactor, String]
rules = [MyApp.LintRules.ModuledocRule]

{violations, errors} = SparkLint.run(rules, modules)

Enum.each(violations, fn v ->
  IO.puts("[#{v.severity}] #{v.rule}: #{inspect(v.module)}")
  IO.puts("  #{v.message}")
end)
```

Output:

```
[error] missing_moduledoc: MyApp.Resource
  Elixir.MyApp.Resource is missing @moduledoc
[error] missing_moduledoc: MyApp.Reactor
  Elixir.MyApp.Reactor is missing @moduledoc
```

---

## Rule Anatomy

### The Behaviour Signature

Every rule implements a single callback:

```elixir
@callback check(module :: module(), context :: SparkLint.Context.t()) ::
            {:ok, [SparkLint.Violation.t()]} | {:error, term()}
```

- **`module`** — a single atom (e.g., `MyApp.Resource`)
- **`context`** — struct with `:module`, `:modules`, and `:metadata`
- **Returns:**
  - `{:ok, []}` — no violations found
  - `{:ok, [v1, v2]}` — violations found; runner will sort them
  - `{:error, "reason"}` — rule crashed; runner collects this for debugging

### Violations Struct

```elixir
%SparkLint.Violation{
  rule: :your_rule_id,           # atom, no spaces
  module: Module,                # the module being checked
  message: "Human description",  # shown to users
  severity: :error,              # :error | :warning | :info
  step: nil,                     # optional: for Reactor-scoped violations
  attribute: nil                 # optional: for attribute-scoped violations
}
```

### Severity Levels

- **`:error`** — fails CI; must be fixed before merging
- **`:warning`** — visible but non-blocking; can ship with approval
- **`:info`** — informational; never blocks

The runner sorts violations with errors first, then warnings, then info. Within each severity, violations are sorted alphabetically by module name.

---

## Testing Rules

### Unit Test Example

```elixir
# test/my_app/lint_rules/moduledoc_rule_test.exs

defmodule MyApp.LintRules.ModuledocRuleTest do
  use ExUnit.Case

  alias MyApp.LintRules.ModuledocRule
  alias SparkLint.Context

  defmodule WithDoc do
    @moduledoc "I have docs"
  end

  defmodule WithoutDoc do
  end

  test "passes module with @moduledoc" do
    ctx = %Context{module: WithDoc, modules: [WithDoc], metadata: %{}}
    {:ok, violations} = ModuledocRule.check(WithDoc, ctx)
    assert violations == []
  end

  test "fails module without @moduledoc" do
    ctx = %Context{module: WithoutDoc, modules: [WithoutDoc], metadata: %{}}
    {:ok, violations} = ModuledocRule.check(WithoutDoc, ctx)
    assert length(violations) == 1
    assert hd(violations).rule == :missing_moduledoc
    assert hd(violations).severity == :error
  end

  test "handles non-modules gracefully" do
    # Simulate checking a built-in module
    ctx = %Context{module: String, modules: [String], metadata: %{}}
    {:ok, violations} = ModuledocRule.check(String, ctx)
    # Built-in modules have docs, so no violation
    assert violations == []
  end
end
```

### Integration Test Example

```elixir
# test/my_app/lint_integration_test.exs

defmodule MyApp.LintIntegrationTest do
  use ExUnit.Case

  test "runner collects violations from all modules" do
    modules = [
      MyApp.LintRules.ModuledocRuleTest.WithDoc,
      MyApp.LintRules.ModuledocRuleTest.WithoutDoc
    ]
    rules = [MyApp.LintRules.ModuledocRule]

    {violations, errors} = SparkLint.run(rules, modules)

    assert length(violations) == 1
    assert errors == []
  end

  test "runner collects rule errors" do
    defmodule CrashingRule do
      @behaviour SparkLint.Rule
      def check(_, _), do: {:error, "Boom!"}
    end

    modules = [String]
    rules = [CrashingRule]

    {violations, errors} = SparkLint.run(rules, modules)

    assert violations == []
    assert length(errors) == 1
    assert hd(errors).reason == "Boom!"
  end
end
```

---

## Error Handling

### Always Graceful Degradation

If a rule might crash, wrap risky code in `try/rescue` and return `{:ok, []}`:

```elixir
def check(module, _ctx) do
  try do
    # Risky operation that might fail
    info = Ash.Resource.Info.attributes(module)
    violations = check_attributes(info, module)
    {:ok, violations}
  rescue
    e ->
      # Log for debugging, but don't fail the rule
      IO.warn("ModuleChecker failed for #{inspect(module)}: #{inspect(e)}")
      {:ok, []}
  end
end
```

### When to Return `{:error, reason}`

Return `{:error, reason}` only if you want the runner to collect the error for debugging. Use this sparingly:

```elixir
def check(module, ctx) do
  case fetch_something(module) do
    {:ok, data} -> {:ok, check_data(data, module)}
    {:error, reason} -> {:error, "Failed to fetch data: #{reason}"}
  end
end
```

The runner will include this error in the `{violations, errors}` tuple, visible to the caller.

---

## Using Metadata

Metadata is how rules receive application context (project root, sensitive modules, manifest, etc.).

### Passing Metadata

```elixir
{violations, errors} = SparkLint.run(
  [Rule1, Rule2],
  [Module1, Module2],
  %{
    metadata: %{
      project_root: "/home/user/myapp",
      sensitive_modules: [MyApp.Finance, MyApp.Users],
      manifest: parsed_manifest,
      custom_key: "custom_value"
    }
  }
)
```

### Accessing Metadata

```elixir
def check(module, ctx) do
  project_root = ctx.metadata[:project_root]
  sensitive = ctx.metadata[:sensitive_modules] || []

  if module in sensitive do
    check_sensitive(module, project_root)
  else
    {:ok, []}
  end
end
```

### Metadata Conventions

Document which metadata keys your rule expects:

```elixir
@moduledoc """
Checks that sensitive resources use AshPaperTrail.

Uses metadata:
  - `:sensitive_modules` — list of module atoms
  - `:project_root` — project root path (optional)
"""
```

---

## Advanced Patterns

### Cross-Module Analysis

Use `ctx.modules` to reference other modules:

```elixir
@moduledoc """
Checks that all referenced resources are included in the manifest.
"""

def check(module, ctx) do
  # Find all modules referenced by this one
  referenced = find_references(module)

  # Check if they're in the linted set
  untracked = referenced -- ctx.modules

  if untracked == [] do
    {:ok, []}
  else
    {:ok,
     Enum.map(untracked, fn m ->
       %SparkLint.Violation{
         rule: :untracked_reference,
         module: module,
         message: "#{inspect(module)} references untracked module #{inspect(m)}",
         severity: :warning
       }
     end)}
  end
rescue
  _ -> {:ok, []}
end
```

### File System Checks

```elixir
def check(module, ctx) do
  project_root = ctx.metadata[:project_root] || File.cwd!()

  case check_runbook_file(module, project_root) do
    true -> {:ok, []}
    false ->
      {:ok,
       [
         %SparkLint.Violation{
           rule: :missing_runbook_file,
           module: module,
           message: "No runbook found for #{inspect(module)}",
           severity: :error
         }
       ]}
  end
rescue
  _ -> {:ok, []}
end

defp check_runbook_file(module, project_root) do
  runbook_path = Path.join(project_root, "docs/runbooks/#{module}.md")
  File.exists?(runbook_path)
end
```

### Conditional Rules

```elixir
@moduledoc """
Only checks modules in the sensitive_modules list.
"""

def check(module, ctx) do
  sensitive = ctx.metadata[:sensitive_modules] || []

  if module in sensitive do
    check_sensitive(module)
  else
    {:ok, []}
  end
end

defp check_sensitive(module) do
  # Stricter checks for sensitive modules
  # ...
end
```

### Attribute-Level Violations

```elixir
@moduledoc """
Checks that all Ash resource attributes have descriptions.
"""

def check(module, _ctx) do
  try do
    attributes = Ash.Resource.Info.attributes(module)

    violations =
      Enum.flat_map(attributes, fn attr ->
        if is_nil(attr.description) or attr.description == "" do
          [
            %SparkLint.Violation{
              rule: :missing_attribute_description,
              module: module,
              message: "#{attr.name} is missing a description",
              severity: :error,
              attribute: attr.name
            }
          ]
        else
          []
        end
      end)

    {:ok, violations}
  rescue
    _ -> {:ok, []}
  end
end
```

### Step-Level Violations (for Reactors)

```elixir
@moduledoc """
Checks that side-effect steps in reactors have names.
"""

def check(module, _ctx) do
  try do
    info = Foundry.SparkMeta.walk(module)

    violations =
      Enum.flat_map(info.steps, fn step ->
        if step.type in [:create, :update, :destroy] and is_nil(step.name) do
          [
            %SparkLint.Violation{
              rule: :unnamed_side_effect_step,
              module: module,
              message: "Side-effect step has no name",
              severity: :warning,
              step: step.ref
            }
          ]
        else
          []
        end
      end)

    {:ok, violations}
  rescue
    _ -> {:ok, []}
  end
end
```

---

## Common Mistakes

### ❌ Letting Exceptions Propagate

```elixir
# BAD: Will crash the entire lint run
def check(module, _ctx) do
  attributes = Ash.Resource.Info.attributes(module)  # Crashes if module is not a Resource
  {:ok, check_attributes(attributes)}
end

# GOOD: Handles the error gracefully
def check(module, _ctx) do
  try do
    attributes = Ash.Resource.Info.attributes(module)
    {:ok, check_attributes(attributes)}
  rescue
    _ -> {:ok, []}
  end
end
```

### ❌ Forgetting Metadata is Optional

```elixir
# BAD: Crashes if :sensitive_modules is missing
sensitive = ctx.metadata[:sensitive_modules]

# GOOD: Provides a default
sensitive = ctx.metadata[:sensitive_modules] || []
```

### ❌ Not Documenting Metadata Requirements

```elixir
# BAD: Rule uses undocumented metadata
def check(module, ctx) do
  some_config = ctx.metadata[:some_config]
  # User has no idea what metadata to provide
end

# GOOD: Documents what metadata is needed
@moduledoc """
Uses metadata:
  - `:some_config` — configuration map
"""
```

### ❌ Creating Too Many Violations Per Module

```elixir
# BAD: One violation per field, can be noisy
attributes = get_attributes(module)

violations =
  Enum.map(attributes, fn attr ->
    if is_nil(attr.doc) do
      %SparkLint.Violation{rule: :no_doc, module: module, ...}
    end
  end)

# GOOD: Roll up related violations
if Enum.any?(attributes, &is_nil(&1.doc)) do
  [%SparkLint.Violation{
    rule: :missing_docs,
    module: module,
    message: "#{module} has #{count_undocumented(attributes)} undocumented fields",
    severity: :warning
  }]
else
  []
end
```

---

## Next Steps

- Read the [SparkLint README](./README.md) for API reference
- Check [Foundry's rules](https://github.com/anthropics/foundry) for real-world examples
- Publish your rules as a Hex package
