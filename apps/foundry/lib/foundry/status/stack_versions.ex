defmodule Foundry.Status.StackVersions do
  @moduledoc """
  Extracts resolved stack dependency versions from mix.lock.
  """

  @tracked ~w[elixir ash ash_postgres phoenix reactor oban]a

  def read(project_root) do
    case Foundry.MixLock.read_versions(project_root, @tracked) do
      {:error, _} ->
        Map.new(@tracked, fn lib ->
          {to_string(lib), nil}
        end)

      versions ->
        Map.new(@tracked, fn lib ->
          {to_string(lib), Map.get(versions, lib)}
        end)
    end
  end
end
