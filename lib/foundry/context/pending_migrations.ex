defmodule Foundry.Context.PendingMigrations do
  @moduledoc """
  Determines which modules have pending Ash migrations by running
  `mix ash.codegen --check` once per project invocation.

  Do not call check/1 per module — it spawns one Mix process per call.
  Call once, then use pending?/2 to query individual modules.
  """

  @spec check(project_root :: String.t()) :: {:ok, MapSet.t()} | {:error, term()}
  def check(project_root) do
    case System.cmd("mix", ["ash.codegen", "--check"],
           cd: project_root, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, MapSet.new()}

      {output, _nonzero} ->
        {:ok, MapSet.new(parse_pending_modules(output))}
    end
  end

  @spec pending?(module :: module(), pending_set :: MapSet.t()) :: boolean()
  def pending?(module, pending_set), do: MapSet.member?(pending_set, module)

  defp parse_pending_modules(output) do
    # ash.codegen --check output format is implementation-specific.
    # Adjust the regex to match the actual output of the ash_postgres version in use.
    Regex.scan(~r/\b([\w.]+)\b.*?pending migration/, output)
    |> Enum.flat_map(fn [_, mod] ->
      try do [String.to_existing_atom(mod)]
      rescue _ -> []
      end
    end)
  end
end
