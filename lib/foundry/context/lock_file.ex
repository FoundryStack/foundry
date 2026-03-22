defmodule Foundry.Context.LockFile do
  @moduledoc """
  Manages the context lock file (.foundry/context.lock) which tracks whether
  the cached project context is fresh.

  The lock file stores a SHA256 hash of all lib/**/*.ex and test/**/*.ex files.
  If any of these files change, the hash becomes stale.
  """

  @lock_path ".foundry/context.lock"

  @spec compute_hash(String.t()) :: String.t()
  def compute_hash(project_root) do
    # Deterministic: sort files, hash each file's content individually,
    # then hash the concatenated per-file hashes. Sorting is mandatory —
    # glob order is filesystem-dependent and non-deterministic across platforms.
    files =
      [Path.join(project_root, "lib/**/*.ex"),
       Path.join(project_root, "test/**/*.ex")]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.sort()

    per_file_hashes =
      Enum.map_join(files, "", fn path ->
        :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
      end)

    :crypto.hash(:sha256, per_file_hashes) |> Base.encode16(case: :lower)
  end

  @spec write(String.t()) :: :ok
  def write(project_root) do
    hash = compute_hash(project_root)
    lock_path = Path.join(project_root, @lock_path)
    File.mkdir_p!(Path.dirname(lock_path))
    File.write!(lock_path, hash <> "\n")
  end

  @spec check(String.t()) :: :ok | {:error, :stale | :missing}
  def check(project_root) do
    case File.read(Path.join(project_root, @lock_path)) do
      {:error, :enoent} -> {:error, :missing}
      {:ok, stored} ->
        current = compute_hash(project_root)
        if String.trim(stored) == current, do: :ok, else: {:error, :stale}
    end
  end
end
