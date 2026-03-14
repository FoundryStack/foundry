defmodule SparkMeta do
  @moduledoc """
  Generic Spark DSL walker → struct tree.

  Provides introspection of Spark DSL modules with an opt-in `SparkMeta.Extension`
  hook for richer output. Unknown extensions get a raw key-value fallback.

  ## Usage

      {:ok, state} = SparkMeta.walk(MyResource)
      # state.extensions contains all Spark extensions
      # state.extension_data contains output from registered SparkMeta.Extension handlers

      # Register a handler for a specific extension:
      SparkMeta.Registry.register(MyExtension, MyExtensionHandler)

      # MyExtensionHandler must implement SparkMeta.Extension behaviour:
      defmodule MyExtensionHandler do
        @behaviour SparkMeta.Extension

        def extract(extension_module, dsl_state) do
          # Return rich data about the extension
          %{custom: "output"}
        end
      end
  """

  defdelegate walk(module), to: SparkMeta.Walker
  defdelegate spark_module?(module), to: SparkMeta.Walker
  defdelegate extensions(module), to: SparkMeta.Walker
  defdelegate entities(module, path), to: SparkMeta.Walker
  defdelegate get_opt(module, path, key, default), to: SparkMeta.Walker
  defdelegate get_persisted(module, key, default), to: SparkMeta.Walker
end
