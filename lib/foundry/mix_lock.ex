defmodule Foundry.MixLock do
  @moduledoc """
  Helpers for reading resolved dependency versions from `mix.lock`.

  `mix.lock` is valid Elixir, but evaluating it on newer Elixir versions emits
  warnings for quoted keyword keys like `"ash":`. Version checks only need the
  resolved Hex version string, so parse that directly instead.
  """

  def read_versions(project_root, deps) do
    path = Path.join(project_root, "mix.lock")

    case File.read(path) do
      {:ok, content} -> versions_from_content(content, deps)
      {:error, _} -> {:error, :enoent}
    end
  end

  def versions_from_content(content, deps) do
    Map.new(deps, fn dep ->
      {dep, version_from_content(content, dep)}
    end)
  end

  def version_from_content(content, dep) do
    dep_name = dep |> to_string() |> Regex.escape()

    pattern =
      ~r/(?:^|\n)\s*(?:"#{dep_name}"|#{dep_name}):\s*\{:hex,\s*:[A-Za-z0-9_?!]+,\s*"([^"]+)"/

    case Regex.run(pattern, content) do
      [_, version] -> version
      _ -> nil
    end
  end
end
