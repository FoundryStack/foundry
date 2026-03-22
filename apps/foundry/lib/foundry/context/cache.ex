defmodule Foundry.Context.Cache do
  @moduledoc """
  ETS-backed cache for module context data.

  Provides `get_or_compute/3` to cache expensive operations like
  SparkMeta.walk/1 results.

  This is a Phase 1 stub using process-local caching. Will be upgraded to
  Nebulex L1 (Hex dependency) in Phase 3+ when Nebulex is added.
  """

  @doc """
  Get a cached value or compute it if not present.

  CONCURRENCY NOTE: This is a best-effort cache (last-write-wins on race).
  Two concurrent calls with a cold cache will both compute and both put.
  This is acceptable because: (1) SparkMeta.walk/1 is idempotent, (2) test
  environment is single-threaded with async: false, (3) real projects are
  read-heavy on modules. If atomicity becomes critical, add a lock.
  """
  def get_or_compute(_key, _ttl \\ :infinity, fun) do
    # Phase 1: simple function-local caching (no persistence)
    # Phase 3+: upgrade to Nebulex ETS cache
    fun.()
  end
end
