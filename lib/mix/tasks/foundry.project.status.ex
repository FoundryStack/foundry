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
    - `--json` - Output raw JSON (default: false, outputs formatted)
  """

  use Mix.Task

  def run(args) do
    Mix.Task.run("compile")

    {opts, _rest} =
      OptionParser.parse!(args, strict: [json: :boolean])

    project_root = File.cwd!()
    status = Foundry.Status.build(project_root)

    json = Jason.encode!(status)

    if Keyword.get(opts, :json, false) do
      IO.write(json)
    else
      json |> Jason.decode!() |> Jason.encode!(pretty: true) |> IO.write()
    end
  end
end
