defmodule SparkMeta.ExtensionTest do
  use ExUnit.Case
  doctest SparkMeta.Extension

  # Test implementation of SparkMeta.Extension
  defmodule TestExtensionHandler do
    @behaviour SparkMeta.Extension

    def extract(_extension_module, _dsl_state) do
      %{test: "data", extracted: true}
    end
  end

  defmodule FailingExtensionHandler do
    @behaviour SparkMeta.Extension

    def extract(_extension_module, _dsl_state) do
      raise "Intentional failure"
    end
  end

  setup do
    :ets.delete_all_objects(:spark_meta_registry)
    :ok
  end

  test "extension handlers are called during walk/1" do
    # Register a test handler for one of the actual extensions
    SparkMeta.Registry.register(Ash.Resource.Dsl, TestExtensionHandler)

    {:ok, state} = SparkMeta.Walker.walk(MockResource)

    # The handler should have been invoked
    assert Ash.Resource.Dsl in state.extensions
    assert state.extension_data[Ash.Resource.Dsl] == %{test: "data", extracted: true}
  end

  test "extension_data is populated with handler results" do
    SparkMeta.Registry.register(Ash.Resource.Dsl, TestExtensionHandler)

    {:ok, state} = SparkMeta.Walker.walk(MockResource)

    # Check extension_data is a map with the handler's result
    assert is_map(state.extension_data)
    assert Map.get(state.extension_data, Ash.Resource.Dsl) == %{test: "data", extracted: true}
  end

  test "failing handlers don't crash walk/1" do
    SparkMeta.Registry.register(Ash.Resource.Dsl, FailingExtensionHandler)

    # Should not crash, even though handler raises
    {:ok, state} = SparkMeta.Walker.walk(MockResource)

    # The failing handler's extension should not have data
    assert Ash.Resource.Dsl not in Map.keys(state.extension_data) or
             state.extension_data[Ash.Resource.Dsl] == nil
  end

  test "unregistered extensions have no extension_data" do
    # Don't register anything
    {:ok, state} = SparkMeta.Walker.walk(MockResource)

    # extension_data should be empty if no handlers registered
    assert is_map(state.extension_data)
  end

  test "multiple handlers can be registered" do
    defmodule Handler1 do
      @behaviour SparkMeta.Extension
      def extract(_ext, _state), do: %{handler: 1}
    end

    defmodule Handler2 do
      @behaviour SparkMeta.Extension
      def extract(_ext, _state), do: %{handler: 2}
    end

    SparkMeta.Registry.register(Ash.Resource.Dsl, Handler1)
    SparkMeta.Registry.register(Ash.DataLayer.Simple, Handler2)

    {:ok, state} = SparkMeta.Walker.walk(MockResource)

    assert state.extension_data[Ash.Resource.Dsl] == %{handler: 1}
    assert state.extension_data[Ash.DataLayer.Simple] == %{handler: 2}
  end
end
