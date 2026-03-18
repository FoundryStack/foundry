defmodule Mix.Tasks.Foundry.Context.All do
  @shortdoc "Emit Spark DSL context for all project modules, grouped by domain (ADR-003)"

  @moduledoc """
  Introspects every Foundry-relevant compiled module in the current project and
  emits a JSON object mapping domain names to arrays of `ModuleContext` objects.

  Output shape:

      {
        "Finance": [ <ModuleContext>, ... ],
        "Players": [ <ModuleContext>, ... ]
      }

  This is used by:
  - `mix foundry.diagram.generate` (reads this output to build the graph)
  - The Phase 2 system map panel (consumes the JSON directly)
  - The copilot engine's initial domain survey on first request in a session

  ## Usage

      mix foundry.context.all
      mix foundry.context.all --json

  ## Context exclusions

  Modules listed in `.foundry/manifest.exs` under `context_exclusions:` are
  silently omitted. Use this as a temporary workaround for cyclic DSL compilation
  issues (see: docs/runbooks/studio_ux_degradation.md).

  ## Performance

  Introspection is parallelised with `Task.async_stream/3` using
  `max_concurrency: System.schedulers_online()`. On a project with 50 modules,
  this typically completes in under 2 seconds on a developer machine.

  ## Schema review gate

  After Phase 1 implementation, run this task against the iGaming reference
  project and verify the output matches the counts declared in
  `docs/reference-project-fixture.md §Expected mix foundry.context.all Output Shape`.
  That check is the Phase 1 schema review gate.
  """

  use Mix.Task

  alias Foundry.Context.Introspector

  @impl Mix.Task
  def run(_args) do
    # Allow target project to skip DB (e.g. igaming_ref without Postgres)
    app = Mix.Project.config()[:app]
    Application.put_env(app, :foundry_tasks_only, true)

    Mix.Task.run("app.start")

    result = Introspector.build_all()

    IO.puts(Jason.encode!(result, pretty: true))
  end
end
