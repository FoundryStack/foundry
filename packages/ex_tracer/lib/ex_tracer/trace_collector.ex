defmodule ExTracer.TraceCollector do
  @moduledoc """
  Receives runtime events during test execution and persists them.
  """

  @callback start(opts :: map()) :: {:ok, state :: any()} | {:error, term()}
  @callback record(state :: any(), event :: map()) :: :ok
  @callback flush(state :: any()) :: :ok
end
