defmodule SparkMeta.Walker do
  @moduledoc """
  Core Spark DSL introspection logic.

  Provides a safe, generic interface for walking Spark DSL modules and extracting
  their structure into `SparkMeta.DslState` structs. All functions except `walk/1`
  wrap Spark calls in `try/rescue` and return safe defaults on any error.
  """

  require Logger

  @doc """
  Check if a module is a Spark module.

  Returns `true` if the module exports `spark_dsl_config/0`, `false` otherwise.
  """
  @spec spark_module?(module()) :: boolean()
  def spark_module?(module) do
    function_exported?(module, :spark_dsl_config, 0)
  end

  @doc """
  Walk a Spark module and return its introspected state.

  Returns `{:ok, DslState.t()}` on success, or one of:
  - `{:error, :not_a_spark_module}` if the module is not a Spark module
  - `{:error, {:not_loaded, module}}` if the module cannot be loaded

  This function calls registered `SparkMeta.Extension` handlers for each extension
  found in the module, storing the results in `extension_data`.
  """
  @spec walk(module()) ::
          {:ok, DslState.t()} | {:error, :not_a_spark_module | {:not_loaded, module()}}
  def walk(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if spark_module?(module) do
          {:ok, do_walk(module)}
        else
          {:error, :not_a_spark_module}
        end

      :error ->
        {:error, {:not_loaded, module}}

      {:error, _reason} ->
        {:error, {:not_loaded, module}}
    end
  end

  defp do_walk(module) do
    extensions = get_extensions_list(module)
    persisted = get_persisted_map(module)

    # Build initial state with eager-loaded extensions and persisted
    state = %SparkMeta.DslState{
      module: module,
      extensions: extensions,
      persisted: persisted,
      extension_data: invoke_extension_handlers(module, extensions)
    }

    state
  end

  defp get_extensions_list(module) do
    try do
      Spark.Dsl.Extension.get_persisted(module, :extensions) || []
    rescue
      _ -> []
    end
  end

  defp get_persisted_map(module) do
    try do
      # Fetch :extensions and :data_layer eagerly
      extensions = Spark.Dsl.Extension.get_persisted(module, :extensions) || []
      data_layer = Spark.Dsl.Extension.get_persisted(module, :data_layer)

      persisted = %{}
      persisted = Map.put(persisted, :extensions, extensions)

      if data_layer do
        Map.put(persisted, :data_layer, data_layer)
      else
        persisted
      end
    rescue
      _ -> %{}
    end
  end

  defp invoke_extension_handlers(module, extensions) do
    extensions
    |> Enum.reduce(%{}, fn ext, acc ->
      case SparkMeta.Registry.handler_for(ext) do
        nil ->
          acc

        handler ->
          try do
            # Create a temporary DslState for the handler to work with
            temp_state = %SparkMeta.DslState{module: module}
            result = handler.extract(ext, temp_state)
            Map.put(acc, ext, result)
          rescue
            e ->
              Logger.debug("Extension handler #{handler} failed for #{ext}: #{inspect(e)}")
              acc
          end
      end
    end)
  end

  @doc """
  Get the list of extensions for a module.

  Returns a list of extension modules, or `[]` if the module is not a Spark module
  or cannot be loaded.
  """
  @spec extensions(module()) :: [module()]
  def extensions(module) do
    try do
      case Code.ensure_loaded(module) do
        {:module, ^module} ->
          get_extensions_list(module)

        :error ->
          []
      end
    rescue
      _ -> []
    end
  end

  @doc """
  Get entities (structs) for a given path in a module.

  Path is a list of atoms representing the DSL path (e.g., `[:attributes]` or `[:relationships]`).
  Returns a list of structs found at that path, or `[]` if not found or an error occurs.
  """
  @spec entities(module(), path :: [atom()]) :: [struct()]
  def entities(module, path) do
    try do
      case Code.ensure_loaded(module) do
        {:module, ^module} ->
          if spark_module?(module) do
            Spark.Dsl.Extension.get_entities(module, path) || []
          else
            []
          end

        :error ->
          []
      end
    rescue
      _ -> []
    end
  end

  @doc """
  Get an option value from a module's DSL.

  Path is a list of atoms (e.g., `[:graphql]`), key is the option atom, and default is returned
  if the option is not found. Returns default on any error.
  """
  @spec get_opt(module(), path :: [atom()], key :: atom(), default :: term()) :: term()
  def get_opt(module, path, key, default) do
    try do
      case Code.ensure_loaded(module) do
        {:module, ^module} ->
          if spark_module?(module) do
            Spark.Dsl.Extension.get_opt(module, path, key, default)
          else
            default
          end

        :error ->
          default
      end
    rescue
      _ -> default
    end
  end

  @doc """
  Get a persisted value from a module's DSL.

  Returns the persisted value for the given key, or default if not found.
  """
  @spec get_persisted(module(), key :: atom(), default :: term()) :: term()
  def get_persisted(module, key, default) do
    try do
      case Code.ensure_loaded(module) do
        {:module, ^module} ->
          if spark_module?(module) do
            case Spark.Dsl.Extension.get_persisted(module, key) do
              nil -> default
              value -> value
            end
          else
            default
          end

        :error ->
          default
      end
    rescue
      _ -> default
    end
  end
end
