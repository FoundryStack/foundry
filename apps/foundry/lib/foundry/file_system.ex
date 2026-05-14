defmodule Foundry.FileSystem do
  @moduledoc """
  Validated file read boundary for all project file access in channels and controllers.

  All file reads that originate from the Studio UI or copilot shell must go through
  this module. Direct `File.read!/1` calls from channels are forbidden (enforced by
  `Foundry.LintRules.FileWriteRule` in later phases).

  See ADR-020 §File system access via Foundry.FileSystem.
  """

  # Directory prefixes — any file under these paths is permitted.
  @permitted_dirs [
    "lib/",
    "test/",
    "config/",
    "priv/repo/migrations/",
    "docs/adrs/",
    "docs/findings/",
    "docs/runbooks/",
    "docs/regulations/",
    ".foundry/usage_rules/"
  ]

  # Exact file paths — only the specific file is permitted, not any file
  # whose path begins with the same string.
  @permitted_exact [
    "AGENTS.md",
    "mix.exs",
    ".foundry/manifest.exs"
  ]

  @type read_error :: :outside_boundary | :not_found | File.posix()

  @spec read(project_root :: String.t(), relative_path :: String.t()) ::
          {:ok, String.t()} | {:error, read_error()}
  def read(project_root, relative_path) do
    root = Path.expand(project_root)
    expanded = Path.expand(Path.join(root, relative_path))

    if permitted?(expanded, root) do
      case File.read(expanded) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :outside_boundary}
    end
  end

  defp permitted?(expanded, root) do
    dir_permitted?(expanded, root) or exact_permitted?(expanded, root)
  end

  defp dir_permitted?(expanded, root) do
    # A file is directory-permitted if its absolute path falls under
    # root/<permitted_dir>. We add a "/" after the expanded prefix to avoid
    # matching "root/lib_extra/foo.ex" when the permitted dir is "lib/":
    # Path.join("root", "lib/") expands to "root/lib", so we append "/" to form
    # "root/lib/" as the required prefix.
    Enum.any?(@permitted_dirs, fn dir ->
      prefix = Path.join(root, dir) <> "/"
      String.starts_with?(expanded, prefix) or expanded == Path.join(root, dir)
    end)
  end

  defp exact_permitted?(expanded, root) do
    # Exact-path entries: the expanded path must equal root + exact, nothing more.
    Enum.any?(@permitted_exact, fn exact ->
      expanded == Path.join(root, exact)
    end)
  end
end
