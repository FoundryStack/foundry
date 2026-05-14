defmodule ExTracer.TraceStore do
  @moduledoc """
  Loads runtime traces from a backing store and matches them to tests.
  """

  @callback load(opts :: map()) :: %{optional(String.t()) => [ExTracer.RuntimeTrace.t()]}
  @callback match(ExTracer.RuntimeTrace.t(), test_name :: String.t()) :: boolean()
end
