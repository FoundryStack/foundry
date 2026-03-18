defmodule Mix.Tasks.Foundry.Context do
  @shortdoc "Emit Spark DSL context for a single module as JSON (ADR-003)"

  @moduledoc """
  Introspects a single compiled Ash/Reactor/Rule module and emits its full
  context as a JSON object matching `Foundry.Context.ModuleContext`.

  This is the primary data-fetch tool for the copilot engine. It is called
  on every LLM request for the modules relevant to the user's intent.
  Results are cached in ETS by `{:context, module_name, beam_mtime}` (ADR-015).

  ## Usage

      mix foundry.context MyApp.Finance.Wallet
      mix foundry.context MyApp.Finance.Wallet --json

  The `--json` flag is accepted for pipeline compatibility but is redundant —
  this task always emits JSON.

  ## Prerequisites

  The project must be compiled. Run `mix compile` first if modules are not loaded.
  This task loads the module via `Code.ensure_loaded/1` and will fail with a clear
  error if the module cannot be found.

  ## Error behaviour

  - Module not found → exit 1, error message to stderr
  - Module found but not Foundry-relevant → exit 1, error message to stderr
  - Introspection error on a field → that field returns its zero value; task succeeds
  """

  use Mix.Task

  alias Foundry.Context.Introspector

  @impl Mix.Task
  def run([module_str | _rest]) do
    Mix.Task.run("app.start")

    mod = resolve_module!(module_str)

    case Introspector.build(mod) do
      {:ok, context} ->
        Mix.shell().info(Jason.encode!(context, pretty: true))

      {:error, reason} ->
        Mix.raise("foundry.context failed for #{module_str}: #{reason}")
    end
  end

  def run([]) do
    Mix.raise("""
    Usage: mix foundry.context <ModuleName>

    Example:
      mix foundry.context MyApp.Finance.Wallet
    """)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp resolve_module!(module_str) do
    mod = Module.concat([module_str])

    case Code.ensure_loaded(mod) do
      {:module, ^mod} ->
        mod

      {:error, reason} ->
        Mix.raise("""
        Module #{module_str} could not be loaded: #{inspect(reason)}

        Make sure the project is compiled:
          mix compile
        """)
    end
  end
end
