defmodule Mix.Tasks.Foundry.Project.Status do
  @moduledoc """
  Outputs the current project health status as JSON.

  Usage:
    mix foundry.project.status [--json]

  The status includes:
    - Compilation state
    - Stack dependency versions
    - Lint violations
    - Pending migrations
    - Open proposals
    - Compliance coverage
    - Test coverage
    - CI state
    - Project manifest metadata

  ## Options
    - `--json` - Output compact JSON (default: false, outputs pretty-printed JSON)
  """

  use Mix.Task

  def run(args) do
    Mix.Task.run("compile")

    {opts, _rest} =
      OptionParser.parse!(args, strict: [json: :boolean])

    project_root = File.cwd!()
    pretty = not Keyword.get(opts, :json, false)
    output = build_output(project_root, pretty)
    IO.write(output)
  end

  @doc """
  Build status JSON for the given project root.

  Accepts `pretty: boolean` option. Separated from `run/1` so tests can call
  this without triggering Mix.Task.run("compile") or Mix.Sync.PubSub startup.
  """
  def build_output(project_root, pretty \\ true) do
    status = Foundry.Status.build(project_root)

    if pretty do
      Jason.encode!(status, pretty: true)
    else
      Jason.encode!(status)
    end
  end
end
