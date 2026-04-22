defmodule SparkMeta.AshResourceData do
  @moduledoc false

  def extract(module) do
    %{
      attributes: get_attributes(module),
      relationships: get_relationships(module),
      actions: get_actions(module),
      policies: get_policies(module),
      compliance: get_compliance(module),
      telemetry_prefix: get_telemetry_prefix(module),
      data_layer: get_data_layer(module)
    }
  end

  defp get_module_attribute(module, attribute) do
    try do
      case module.__info__(:attributes)[attribute] do
        nil -> []
        [[_ | _] = value] -> value
        [value] when is_list(value) -> value
        [value] -> [value]
        _ -> []
      end
    rescue
      _ -> []
    end
  end

  defp get_compliance(module), do: get_module_attribute(module, :compliance)
  defp get_telemetry_prefix(module), do: get_module_attribute(module, :telemetry_prefix)

  defp get_data_layer(module) do
    try do
      Ash.Resource.Info.data_layer(module)
    rescue
      _ -> nil
    end
  end

  defp get_attributes(module) do
    try do
      Ash.Resource.Info.attributes(module)
      |> Enum.map(&map_attribute/1)
    rescue
      _ -> []
    end
  end

  defp map_attribute(entity) do
    %{
      name: entity.name,
      type: entity.type,
      description: Map.get(entity, :description),
      allow_nil?: Map.get(entity, :allow_nil?, true),
      default: Map.get(entity, :default),
      sensitive?: Map.get(entity, :sensitive?, false),
      constraints: Map.get(entity, :constraints, []),
      public?: Map.get(entity, :public?, true),
      primary_key?: Map.get(entity, :primary_key?, false),
      generated?: Map.get(entity, :generated?, false),
      __spark_metadata__: Map.get(entity, :__spark_metadata__)
    }
  end

  defp get_relationships(module) do
    try do
      module
      |> Ash.Resource.Info.relationships()
      |> Enum.filter(fn relationship ->
        Map.get(relationship, :public?, true) ||
          not String.starts_with?(to_string(Map.get(relationship, :name, "")), "paper_trail")
      end)
      |> Enum.map(&map_relationship/1)
    rescue
      _ -> []
    end
  end

  defp map_relationship(entity) do
    %{
      name: entity.name,
      type: relationship_type(entity.__struct__),
      destination: entity.destination,
      description: Map.get(entity, :description),
      source_attribute: Map.get(entity, :source_attribute),
      destination_attribute: Map.get(entity, :destination_attribute)
    }
  end

  defp relationship_type(struct_module) do
    case struct_module do
      Ash.Resource.Relationships.BelongsTo -> :belongs_to
      Ash.Resource.Relationships.HasMany -> :has_many
      Ash.Resource.Relationships.HasOne -> :has_one
      Ash.Resource.Relationships.ManyToMany -> :many_to_many
      _ -> :unknown
    end
  end

  defp get_actions(module) do
    try do
      module
      |> Ash.Resource.Info.actions()
      |> Enum.map(&map_action/1)
    rescue
      _ -> []
    end
  end

  defp map_action(entity) do
    %{
      name: entity.name,
      type: entity.type,
      description: Map.get(entity, :description),
      accept: Map.get(entity, :accept, [])
    }
  end

  defp get_policies(module) do
    try do
      module
      |> Spark.Dsl.Extension.get_entities([:policies])
      |> Enum.map(&map_policy/1)
    rescue
      _ -> []
    end
  end

  defp map_policy(entity) do
    %{
      description: Map.get(entity, :description),
      condition: Map.get(entity, :condition)
    }
  end
end
