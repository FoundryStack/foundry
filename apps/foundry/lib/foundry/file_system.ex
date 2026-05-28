defmodule Foundry.FileSystem do
  @moduledoc """
  Validated file read boundary for all project file access in channels and controllers.

  All file reads that originate from the Studio UI or copilot shell must go through
  this module. Direct `File.read!/1` calls from channels are forbidden (enforced by
  `Foundry.LintRules.FileWriteRule` in later phases).

  Permits reading any file within the project root. Path traversal attacks are
  prevented by expanding paths and verifying they remain within the root boundary.

  See ADR-020 §File system access via Foundry.FileSystem.
  """

  @type read_error :: :outside_boundary | :not_found | File.posix()
  @type write_error :: :outside_boundary | File.posix()

  @spec read(project_root :: String.t(), relative_path :: String.t()) ::
          {:ok, String.t()} | {:error, read_error()}
  def read(project_root, relative_path) do
    root = Path.expand(project_root)
    expanded = Path.expand(Path.join(root, relative_path))

    if String.starts_with?(expanded, root <> "/") or expanded == root do
      case File.read(expanded) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :outside_boundary}
    end
  end

  @spec write(project_root :: String.t(), relative_path :: String.t(), content :: String.t()) ::
          :ok | {:error, write_error()}
  def write(project_root, relative_path, content) do
    root = Path.expand(project_root)
    expanded = Path.expand(Path.join(root, relative_path))

    if String.starts_with?(expanded, root <> "/") or expanded == root do
      # Create parent directories if needed
      expanded
      |> Path.dirname()
      |> File.mkdir_p!()

      case File.write(expanded, content) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :outside_boundary}
    end
  end
end
