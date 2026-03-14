defmodule SparkMeta.Extension do
  @moduledoc """
  Behaviour for SparkMeta extension handlers.

  Implementations of this behaviour can register with `SparkMeta.Registry` to provide
  richer output for specific Spark extensions. When a module is walked, registered
  handlers are invoked for each extension found.
  """

  @doc """
  Extract richer data from a Spark extension.

  Called during `SparkMeta.Walker.walk/1` for each extension that has a registered handler.
  Return value is stored in `dsl_state.extension_data[spark_extension_module]`.
  """
  @callback extract(module :: atom(), dsl_state :: SparkMeta.DslState.t()) :: term()
end
