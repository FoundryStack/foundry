# Contributing to SparkLint

Thank you for your interest in contributing! This guide covers:

- [Setting Up Development](#setting-up-development)
- [Code Standards](#code-standards)
- [Running Tests](#running-tests)
- [Submitting Changes](#submitting-changes)
- [Releasing](#releasing)

## Setting Up Development

### Prerequisites

- Elixir ~> 1.15
- Mix (comes with Elixir)

### Clone and Install

```bash
git clone https://github.com/maxsvargal/foundry.git
cd foundry/packages/spark_lint
mix deps.get
```

### Verify Setup

```bash
mix compile
mix test
mix docs
```

## Code Standards

### Style

- Follow the [Elixir Style Guide](https://hexdocs.pm/elixir/code-formatting.html)
- Use `mix format` for formatting (no manual formatting needed)
- Aim for clarity over cleverness

### Module Documentation

Every public module must have `@moduledoc`:

```elixir
defmodule SparkLint.MyModule do
  @moduledoc """
  Concise description of the module's purpose.

  If there's complex behavior, document key functions and patterns here.
  """
end
```

### Function Documentation

Document public functions:

```elixir
@doc """
Brief description.

## Examples

    iex> my_function([:a, :b])
    [:b, :a]
"""
def my_function(list), do: Enum.reverse(list)
```

### Typespecs

Include typespecs for public functions:

```elixir
@spec check(module :: module(), context :: SparkLint.Context.t()) ::
        {:ok, [SparkLint.Violation.t()]} | {:error, term()}
def check(module, context) do
  # ...
end
```

## Running Tests

### All Tests

```bash
mix test
```

### Specific Test File

```bash
mix test test/spark_lint_test.exs
```

### Watch Mode (requires `mix_test_watch`)

```bash
mix test.watch
```

### With Coverage

```bash
mix test --cover
```

## Submitting Changes

### Before You Start

1. Check [open issues](https://github.com/anthropics/foundry/issues) to avoid duplicate work
2. For large changes, open an issue first to discuss approach
3. For rule packages, consider publishing to Hex instead of merging into SparkLint

### Making Changes

1. Create a feature branch: `git checkout -b feature/my-change`
2. Make your changes
3. Run tests: `mix test`
4. Run formatter: `mix format`
5. Commit with a clear message: `git commit -am "Add my feature"`

### Pull Request

1. Push to your fork
2. Open a PR against `main`
3. Describe what changed and why
4. Reference any related issues: "Fixes #123"

### PR Review Process

- At least one maintainer approval required
- All tests must pass
- Code must follow standards (checked via `mix format`)
- No external dependencies allowed in SparkLint core

## Releasing

### Before Release

1. Update version in `mix.exs`
2. Add entry to [CHANGELOG.md](./CHANGELOG.md)
3. Update `README.md` if needed
4. Commit: `git commit -am "v0.2.0"`
5. Tag: `git tag v0.2.0`
6. Push: `git push origin main --tags`

### Publish to Hex

```bash
mix hex.publish
```

This pushes the package to [hex.pm](https://hex.pm) and makes it installable via Hex.

## Package Stability

SparkLint follows [semantic versioning](https://semver.org/):

- **MAJOR** — breaking changes to public API
- **MINOR** — new features, backward-compatible
- **PATCH** — bug fixes

### What's Considered API?

- `SparkLint.run/2` and `SparkLint.run/3` signatures
- `SparkLint.Rule` behaviour
- `SparkLint.Violation` struct fields
- `SparkLint.Context` struct fields

### What's NOT API?

- Internal implementation details (modules in `SparkLint.Runner` internals)
- Error messages (may change without major version bump)
- Performance characteristics

## Questions?

- Open an [issue](https://github.com/anthropics/foundry/issues)
- Check [existing discussions](https://github.com/anthropics/foundry/discussions)
- Review [the guide](./GUIDE.md) for rule-writing patterns

Thanks for contributing!
