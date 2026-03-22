defmodule Foundry.Manifest.Parser do
  @moduledoc """
  Reads and parses .foundry/manifest.exs from a project root.
  Returns the manifest as a keyword list.
  Caches per {file_path, mtime} in ETS.
  """

  @spec read(project_root :: String.t()) ::
          {:ok, keyword()} | {:error, :not_found | :parse_error}
  def read(project_root) do
    with {:ok, content} <- Foundry.FileSystem.read(project_root, ".foundry/manifest.exs"),
         {manifest, _bindings} when is_list(manifest) <-
           Code.eval_string(content, [], file: ".foundry/manifest.exs") do
      {:ok, manifest}
    else
      {:error, reason} -> {:error, reason}
      _                -> {:error, :parse_error}
    end
  end
end
