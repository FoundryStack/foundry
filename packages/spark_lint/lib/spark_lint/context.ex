defmodule SparkLint.Context do
  @moduledoc """
  Passed to each rule during a lint run.

  `metadata` is opaque to SparkLint — the runner never inspects it.
  Rule implementations cast `context.metadata` to access any
  application-specific data (e.g. manifests, project roots).
  """

  defstruct [:module, :modules, metadata: %{}]
end
