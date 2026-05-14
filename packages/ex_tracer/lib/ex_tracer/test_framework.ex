defmodule ExTracer.TestFramework do
  @moduledoc """
  Framework-specific describe/test/property pattern declarations.
  """

  @callback block_patterns() :: [{atom(), arity()}]
  @callback metadata_attrs() :: [atom()]
  @callback test_kinds() :: %{atom() => :test | :property}
end
