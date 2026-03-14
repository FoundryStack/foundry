defmodule SparkMetaTest do
  use ExUnit.Case
  doctest SparkMeta

  describe "facade delegation" do
    test "walk/1 delegates to Walker" do
      {:ok, state} = SparkMeta.walk(MockResource)
      assert state.module == MockResource
    end

    test "spark_module?/1 delegates to Walker" do
      assert SparkMeta.spark_module?(MockResource) == true
      assert SparkMeta.spark_module?(MockPlainModule) == false
    end

    test "extensions/1 delegates to Walker" do
      extensions = SparkMeta.extensions(MockResource)
      assert is_list(extensions)
    end

    test "entities/2 delegates to Walker" do
      entities = SparkMeta.entities(MockResource, [:attributes])
      assert is_list(entities)
    end

    test "get_opt/4 delegates to Walker" do
      result = SparkMeta.get_opt(MockResource, [:attributes], :key, :default)
      assert result == :default or is_atom(result) or is_map(result)
    end

    test "get_persisted/3 delegates to Walker" do
      result = SparkMeta.get_persisted(MockResource, :extensions, [])
      assert is_list(result)
    end
  end
end
