defmodule Foundry.TestScenario.AshTracer do
  @moduledoc """
  Ash.Tracer implementation stub.

  Required for Ash configuration but not currently used since manual
  instrumentation via RuntimeCapture.trace_node is more reliable.
  """

  @behaviour Ash.Tracer

  @impl Ash.Tracer
  def get_span_context do
    :no_span
  end

  @impl Ash.Tracer
  def set_span_context(_context) do
    :ok
  end

  @impl Ash.Tracer
  def start_span(_name, _opts) do
    :ok
  end

  @impl Ash.Tracer
  def set_metadata(_key, _metadata) do
    :ok
  end

  @impl Ash.Tracer
  def set_error(_error) do
    :ok
  end

  @impl Ash.Tracer
  def set_error(_key, _error) do
    :ok
  end

  @impl Ash.Tracer
  def set_handled_error(_key, _error) do
    :ok
  end

  @impl Ash.Tracer
  def stop_span do
    :ok
  end

  @impl Ash.Tracer
  def trace_type?(_type) do
    false
  end
end
