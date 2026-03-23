# SparkLint on Hex

This document describes how SparkLint is organized on [Hex](https://hex.pm) and how documentation is structured.

## Package Information

- **Package Name:** `spark_lint`
- **Repository:** https://github.com/anthropics/foundry
- **Documentation:** https://hexdocs.pm/spark_lint

## Documentation Structure

SparkLint provides three main documentation resources:

### 1. README (Quick Start)

[README.md](./README.md) — Start here.

- What SparkLint is and why you'd use it
- 3-minute quick start
- High-level API overview
- Design principles
- Publishing rules to Hex

### 2. GUIDE (Implementation)

[GUIDE.md](./GUIDE.md) — Learn how to build rules.

- Detailed walkthrough of building your first rule
- Rule anatomy and patterns
- Testing rules
- Error handling
- Using metadata
- Advanced patterns
- Common mistakes

### 3. API Reference

Generated via `mix docs` from inline code documentation.

Core modules:

- `SparkLint` — public API (`run/2`, `run/3`)
- `SparkLint.Rule` — behaviour definition
- `SparkLint.Violation` — violation struct
- `SparkLint.Context` — context struct
- `SparkLint.Runner` — low-level runner (internal)

## Building and Viewing Docs Locally

```bash
# Generate HTML docs
mix docs

# Open in browser (on macOS)
open doc/index.html
```

## Contributing to Docs

Documentation is maintained in:

- `README.md` — package overview and quick start
- `GUIDE.md` — implementation patterns and examples
- `CONTRIBUTING.md` — development guidelines
- Inline `@moduledoc` and `@doc` strings in source files

When adding a public function, include:

```elixir
@doc """
Brief one-liner description.

Longer explanation if complex.

## Examples

    iex> SparkLint.run([MyRule], [MyModule])
    {[%SparkLint.Violation{...}], []}
"""
def run(rules, modules, base_context \\ %{}) do
  # ...
end
```

## Publishing

To publish SparkLint to Hex:

1. Update version in `mix.exs`
2. Update `CHANGELOG.md`
3. Commit: `git commit -am "v0.2.0"`
4. Tag: `git tag v0.2.0`
5. Run: `mix hex.publish`

Hex will:

- Package the code
- Generate documentation from source
- Host on hex.pm and hexdocs.pm
- Index for Hex search

## Documentation Structure on Hex

When published, users see:

```
spark_lint v0.1.0
├── README (auto-linked from Hex)
├── GitHub (linked from Hex)
├── API Reference
│   ├── SparkLint
│   ├── SparkLint.Rule
│   ├── SparkLint.Violation
│   └── SparkLint.Context
└── Guides (from GUIDE.md, if configured)
```

## Links and SEO

- **GitHub**: Link to repo in `mix.exs` as `source_url`
- **Docs**: Link to guides in `mix.exs` as `docs`
- **Homepage**: Link to website in `mix.exs` as `homepage_url`

Example in mix.exs:

```elixir
def project do
  [
    source_url: "https://github.com/anthropics/foundry/tree/main/packages/spark_lint",
    docs: [
      main: "SparkLint",
      extras: ["README.md", "GUIDE.md", "CONTRIBUTING.md", "CHANGELOG.md"]
    ],
    homepage_url: "https://github.com/anthropics/foundry"
  ]
end
```

## For Rule Package Authors

If you're publishing a rule package that depends on SparkLint:

1. Add `:spark_lint` to your `mix.exs`
2. Implement rules following the `SparkLint.Rule` behaviour
3. Document which metadata keys your rules expect
4. Publish to Hex
5. Mention SparkLint in your package docs

Example for a rule package `my_lint_rules`:

```elixir
# mix.exs
defp deps do
  [
    {:spark_lint, "~> 0.1"}
  ]
end

# README.md
This package provides lint rules for [SparkLint](https://hex.pm/packages/spark_lint).
```

Users install both:

```elixir
defp deps do
  [
    {:spark_lint, "~> 0.1"},
    {:my_lint_rules, "~> 0.1"}
  ]
end
```

And configure:

```elixir
# config/config.exs
config :spark_lint, :rules, [
  MyLintRules.MyRule
]

config :spark_lint, :modules_fn, &MyApp.Discovery.all_modules/0
```
