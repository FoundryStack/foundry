defmodule Foundry.Status.StackVersions do
  @moduledoc """
  Extracts resolved stack dependency versions from mix.lock.
  """

  @tracked ~w[elixir ash ash_postgres phoenix reactor oban]a

  def read(project_root) do
    path = Path.join(project_root, "mix.lock")

    case File.read(path) do
      {:error, _} ->
        Map.new(@tracked, fn lib ->
          {to_string(lib), nil}
        end)

      {:ok, content} ->
        {lock, _} = Code.eval_string(content)

        Map.new(@tracked, fn lib ->
          {to_string(lib), extract_version(lock, lib)}
        end)
    end
  end

  defp extract_version(lock, lib) do
    # Code.eval_string creates atom keys from the mix.lock file
    case Map.get(lock, lib) do
      nil ->
        nil

      {:hex, _pkg, version, _, _, _, _, _} ->
        version

      {:hex, _pkg, version, _, _, _, _} ->
        version

      {:git, _url, ref, _opts} ->
        ref

      _other ->
        nil
    end
  end
end
