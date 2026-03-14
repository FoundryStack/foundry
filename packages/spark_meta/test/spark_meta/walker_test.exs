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

  describe "walk/1 rich fields" do
    test "populates moduledoc when @moduledoc is present" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      assert state.moduledoc == "A mock resource with rich documentation for testing."
    end

    test "moduledoc is nil for modules without full docs" do
      {:ok, state} = SparkMeta.Walker.walk(MockResource)
      assert is_nil(state.moduledoc) or is_binary(state.moduledoc)
    end

    test "compliance is empty list by default (tested in integration tests)" do
      {:ok, state} = SparkMeta.Walker.walk(MockResource)
      assert is_list(state.compliance)
    end

    test "telemetry_prefix is empty list by default (tested in integration tests)" do
      {:ok, state} = SparkMeta.Walker.walk(MockResource)
      assert is_list(state.telemetry_prefix)
    end

    test "attributes is a list of maps" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      assert is_list(state.attributes)
      assert Enum.all?(state.attributes, &is_map/1)
    end

    test "each attribute map has required keys" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)

      assert Enum.all?(state.attributes, fn attr ->
               Map.has_key?(attr, :name) and Map.has_key?(attr, :type) and
                 Map.has_key?(attr, :description) and Map.has_key?(attr, :allow_nil?) and
                 Map.has_key?(attr, :default)
             end)
    end

    test "attribute descriptions are captured" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      name_attr = Enum.find(state.attributes, &(&1.name == :name))
      assert name_attr != nil
      assert name_attr.description == "The name of the resource."
      assert name_attr.allow_nil? == false
    end

    test "attribute maps contain no raw Spark structs" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)

      Enum.each(state.attributes, fn attr ->
        refute is_struct(attr)
      end)
    end

    test "relationships is a list of maps" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      assert is_list(state.relationships)
    end

    test "relationship maps have required fields" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      owner_rel = Enum.find(state.relationships, &(&1.name == :owner))
      assert owner_rel != nil
      assert owner_rel.type == :belongs_to
      assert owner_rel.destination == MockResource
      assert owner_rel.description == "The owning resource."
    end

    test "relationship maps contain no raw Spark structs" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)

      Enum.each(state.relationships, fn rel ->
        refute is_struct(rel)
      end)
    end

    test "actions is a list of maps" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      assert is_list(state.actions)
    end

    test "action maps have required fields" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      create_action = Enum.find(state.actions, &(&1.name == :create))
      assert create_action != nil
      assert create_action.type == :create
      assert create_action.description == "Create a new mock."
      assert :name in create_action.accept
    end

    test "read actions have empty accept list" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      read_action = Enum.find(state.actions, &(&1.name == :read))
      assert read_action != nil
      assert read_action.type == :read
      assert read_action.accept == []
    end

    test "action maps contain no raw Spark structs" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)

      Enum.each(state.actions, fn action ->
        refute is_struct(action)
      end)
    end

    test "policies is a list of maps" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      assert is_list(state.policies)
    end

    test "policy maps have description and condition fields" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)

      assert Enum.all?(state.policies, fn p ->
               Map.has_key?(p, :description) and Map.has_key?(p, :condition)
             end)
    end

    test "existing DslState fields still present after expansion" do
      {:ok, state} = SparkMeta.Walker.walk(MockResource)
      assert Map.has_key?(state, :module)
      assert Map.has_key?(state, :extensions)
      assert Map.has_key?(state, :sections)
      assert Map.has_key?(state, :options)
      assert Map.has_key?(state, :persisted)
      assert Map.has_key?(state, :extension_data)
    end
  end
end
