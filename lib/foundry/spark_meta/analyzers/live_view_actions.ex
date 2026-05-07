defmodule Foundry.SparkMeta.Analyzers.LiveViewActions do
  @moduledoc """
  Scans LiveView module source to infer Ash action calls.
  """

  alias Foundry.PageMetadata

  @doc """
  Extract Ash action calls from a LiveView module.

  Returns a list of maps with `resource` and `action` keys:
  - `resource` is the Ash resource module name (string) being acted upon
  - `action` is `:read` or `:write` (or specific action name)

  Prioritizes AST scanning for actual Ash calls and uses `@calls_actions`
  source annotations only to supplement cases the AST cannot see directly.
  """
  @spec analyze(module()) :: [map()]
  def analyze(mod) do
    PageMetadata.calls_actions(mod)
  end
end
