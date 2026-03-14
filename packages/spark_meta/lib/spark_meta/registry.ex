defmodule SparkMeta.Registry do
  @moduledoc """
  ETS-backed GenServer for registering SparkMeta.Extension handlers.

  Handlers are registered by Spark extension module and retrieved by direct ETS lookup (hot path).
  Writes are serialized through the GenServer to prevent table corruption.
  """

  use GenServer
  require Logger

  @table_name :spark_meta_registry

  # Public API

  @doc """
  Register a handler for a Spark extension.

  Returns `:ok` if the registration succeeds.
  """
  @spec register(spark_extension :: atom(), handler :: atom()) :: :ok
  def register(spark_extension, handler) do
    GenServer.call(__MODULE__, {:register, spark_extension, handler})
  end

  @doc """
  Get the handler for a Spark extension, if registered.

  Returns the handler module or `nil` if not registered. This is a direct ETS read (hot path).
  """
  @spec handler_for(spark_extension :: atom()) :: atom() | nil
  def handler_for(spark_extension) do
    case :ets.lookup(@table_name, spark_extension) do
      [{^spark_extension, handler}] -> handler
      [] -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Get all registered handlers.

  Returns a list of `{spark_extension, handler}` tuples.
  """
  @spec all() :: [{atom(), atom()}]
  def all do
    :ets.tab2list(@table_name)
  rescue
    _ -> []
  end

  # GenServer callbacks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :set, :public, {:read_concurrency, true}])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, spark_extension, handler}, _from, state) do
    :ets.insert(@table_name, {spark_extension, handler})
    {:reply, :ok, state}
  end
end
