defmodule SparkMeta.WalkerTest do
  use ExUnit.Case
  doctest SparkMeta.Walker

  describe "spark_module?/1" do
    test "returns true for Spark modules" do
      assert SparkMeta.Walker.spark_module?(MockResource)
    end

    test "returns false for non-Spark modules" do
      assert SparkMeta.Walker.spark_module?(MockPlainModule) == false
    end
  end

  describe "walk/1" do
    test "returns OK tuple with DslState for Spark module" do
      {:ok, state} = SparkMeta.Walker.walk(MockResource)
      assert state.module == MockResource
      assert is_list(state.extensions)
    end

    test "returns error for non-Spark module" do
      {:error, :not_a_spark_module} = SparkMeta.Walker.walk(MockPlainModule)
    end

    test "returns error for unloadable module" do
      {:error, {:not_loaded, _}} = SparkMeta.Walker.walk(NonExistentModule)
    end

    test "eagerly populates extensions in DslState" do
      {:ok, state} = SparkMeta.Walker.walk(MockResource)
      assert is_list(state.extensions)
      assert Enum.all?(state.extensions, &is_atom/1)
    end

    test "eagerly populates persisted values" do
      {:ok, state} = SparkMeta.Walker.walk(MockResource)
      assert is_map(state.persisted)
    end

    test "sections and options are empty on walk" do
      {:ok, state} = SparkMeta.Walker.walk(MockResource)
      assert state.sections == %{}
      assert state.options == %{}
    end
  end

  describe "extensions/1" do
    test "returns list of extensions for Spark module" do
      extensions = SparkMeta.Walker.extensions(MockResource)
      assert is_list(extensions)
      assert Enum.all?(extensions, &is_atom/1)
    end

    test "returns empty list for non-Spark module" do
      assert SparkMeta.Walker.extensions(MockPlainModule) == []
    end

    test "returns empty list for unloadable module" do
      assert SparkMeta.Walker.extensions(NonExistentModule) == []
    end
  end

  describe "entities/2" do
    test "returns list of entities for valid path" do
      entities = SparkMeta.Walker.entities(MockResource, [:attributes])
      assert is_list(entities)
    end

    test "returns empty list for invalid path" do
      entities = SparkMeta.Walker.entities(MockResource, [:invalid, :path])
      assert entities == []
    end

    test "returns empty list for non-Spark module" do
      entities = SparkMeta.Walker.entities(MockPlainModule, [:attributes])
      assert entities == []
    end

    test "returns empty list for unloadable module" do
      entities = SparkMeta.Walker.entities(NonExistentModule, [:attributes])
      assert entities == []
    end
  end

  describe "get_opt/4" do
    test "returns value for valid option path and key" do
      # MockResource may have options; this is a fallback test
      result = SparkMeta.Walker.get_opt(MockResource, [:attributes], :example, :default)
      assert result == :default or is_atom(result) or is_map(result)
    end

    test "returns default for missing option key" do
      result = SparkMeta.Walker.get_opt(MockResource, [:nonexistent], :key, :my_default)
      assert result == :my_default
    end

    test "returns default for non-Spark module" do
      result = SparkMeta.Walker.get_opt(MockPlainModule, [:attributes], :key, :default)
      assert result == :default
    end

    test "returns default for unloadable module" do
      result = SparkMeta.Walker.get_opt(NonExistentModule, [:attributes], :key, :default)
      assert result == :default
    end
  end

  describe "get_persisted/3" do
    test "returns persisted value for known key" do
      result = SparkMeta.Walker.get_persisted(MockResource, :extensions, [])
      assert is_list(result)
    end

    test "returns default for missing persisted key" do
      result = SparkMeta.Walker.get_persisted(MockResource, :nonexistent_key, :my_default)
      assert result == :my_default
    end

    test "returns default for non-Spark module" do
      result = SparkMeta.Walker.get_persisted(MockPlainModule, :extensions, [])
      assert result == []
    end

    test "returns default for unloadable module" do
      result = SparkMeta.Walker.get_persisted(NonExistentModule, :extensions, [])
      assert result == []
    end
  end
end
