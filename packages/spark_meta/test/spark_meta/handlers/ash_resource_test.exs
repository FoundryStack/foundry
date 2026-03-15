defmodule SparkMeta.Handlers.AshResourceTest do
  use ExUnit.Case

  setup do
    :ets.delete_all_objects(:spark_meta_registry)
    SparkMeta.Registry.register(Ash.Resource.Dsl, SparkMeta.Handlers.AshResource)
    :ok
  end

  describe "extract/2 directly" do
    test "returns a map with all expected keys" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      assert is_map(result)
      assert Map.has_key?(result, :attributes)
      assert Map.has_key?(result, :relationships)
      assert Map.has_key?(result, :actions)
      assert Map.has_key?(result, :policies)
      assert Map.has_key?(result, :compliance)
      assert Map.has_key?(result, :telemetry_prefix)
    end

    test "attributes is a list of plain maps with required keys" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      assert is_list(result.attributes)

      assert Enum.all?(result.attributes, fn attr ->
               Map.has_key?(attr, :name) and Map.has_key?(attr, :type) and
                 Map.has_key?(attr, :description) and Map.has_key?(attr, :allow_nil?) and
                 Map.has_key?(attr, :default)
             end)
    end

    test "attribute descriptions are captured" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      name_attr = Enum.find(result.attributes, &(&1.name == :name))
      assert name_attr != nil
      assert name_attr.description == "The name of the resource."
      assert name_attr.allow_nil? == false
    end

    test "attribute maps contain no raw Spark structs" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      Enum.each(result.attributes, fn attr -> refute is_struct(attr) end)
    end

    test "relationship type is resolved to atom" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      owner_rel = Enum.find(result.relationships, &(&1.name == :owner))
      assert owner_rel != nil
      assert owner_rel.type == :belongs_to
      assert owner_rel.destination == MockResource
      assert owner_rel.description == "The owning resource."
    end

    test "relationship maps contain no raw Spark structs" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      Enum.each(result.relationships, fn rel -> refute is_struct(rel) end)
    end

    test "action maps have required fields" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      create_action = Enum.find(result.actions, &(&1.name == :create))
      assert create_action != nil
      assert create_action.type == :create
      assert create_action.description == "Create a new mock."
      assert :name in create_action.accept
    end

    test "read actions have empty accept list" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      read_action = Enum.find(result.actions, &(&1.name == :read))
      assert read_action != nil
      assert read_action.type == :read
      assert read_action.accept == []
    end

    test "action maps contain no raw Spark structs" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      Enum.each(result.actions, fn action -> refute is_struct(action) end)
    end

    test "policy maps have description and condition fields" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)

      assert Enum.all?(result.policies, fn p ->
               Map.has_key?(p, :description) and Map.has_key?(p, :condition)
             end)
    end

    test "compliance defaults to empty list" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      assert is_list(result.compliance)
    end

    test "telemetry_prefix defaults to empty list" do
      state = %SparkMeta.DslState{module: MockResourceWithDocs}
      result = SparkMeta.Handlers.AshResource.extract(Ash.Resource.Dsl, state)
      assert is_list(result.telemetry_prefix)
    end
  end

  describe "via walk/1 with handler registered" do
    test "extension_data[Ash.Resource.Dsl] is populated" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      assert is_map(state.extension_data[Ash.Resource.Dsl])
    end

    test "Ash-specific data accessible via extension_data key" do
      {:ok, state} = SparkMeta.Walker.walk(MockResourceWithDocs)
      ash_data = state.extension_data[Ash.Resource.Dsl]
      assert is_list(ash_data.attributes)
      assert is_list(ash_data.relationships)
      assert is_list(ash_data.actions)
    end
  end
end
