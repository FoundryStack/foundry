defmodule SparkMeta.Handlers.AshResource do
  @moduledoc """
  SparkMeta.Extension handler for Ash.Resource.Dsl.

  Ash-specific metadata (attributes, relationships, actions, policies,
  compliance tags, and telemetry prefix) from Ash.Resource modules.

  Registered automatically at application start when Ash is loaded.
  """

  @behaviour SparkMeta.Extension

  @type attribute_map :: %{
          name: atom(),
          type: term(),
          description: String.t() | nil,
          allow_nil?: boolean(),
          default: term()
        }

  @type relationship_map :: %{
          name: atom(),
          type: atom(),
          destination: atom(),
          description: String.t() | nil,
          source_attribute: atom() | nil,
          destination_attribute: atom() | nil
        }

  @type action_map :: %{
          name: atom(),
          type: atom(),
          description: String.t() | nil,
          accept: [atom()]
        }

  @type policy_map :: %{
          description: String.t() | nil,
          condition: term()
        }

  @type t :: %{
          attributes: [attribute_map()],
          relationships: [relationship_map()],
          actions: [action_map()],
          policies: [policy_map()],
          compliance: [atom()],
          telemetry_prefix: [atom()]
        }

  @impl SparkMeta.Extension
  def extract(_extension_module, %SparkMeta.DslState{module: module}) do
    %{
      attributes: get_attributes(module),
      relationships: get_relationships(module),
      actions: get_actions(module),
      policies: get_policies(module),
      compliance: get_compliance(module),
      telemetry_prefix: get_telemetry_prefix(module)
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

  defp get_attributes(module) do
    try do
      module
      |> Spark.Dsl.Extension.get_entities([:attributes])
      |> Enum.map(&map_attribute/1)
    rescue
      _ -> []
    end
  end

  defp map_attribute(e) do
    %{
      name: e.name,
      type: e.type,
      description: Map.get(e, :description),
      allow_nil?: Map.get(e, :allow_nil?, true),
      default: Map.get(e, :default)
    }
  end

  defp get_relationships(module) do
    try do
      module
      |> Spark.Dsl.Extension.get_entities([:relationships])
      |> Enum.map(&map_relationship/1)
    rescue
      _ -> []
    end
  end

  defp map_relationship(e) do
    %{
      name: e.name,
      type: relationship_type(e.__struct__),
      destination: e.destination,
      description: Map.get(e, :description),
      source_attribute: Map.get(e, :source_attribute),
      destination_attribute: Map.get(e, :destination_attribute)
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
      |> Spark.Dsl.Extension.get_entities([:actions])
      |> Enum.map(&map_action/1)
    rescue
      _ -> []
    end
  end

  defp map_action(e) do
    %{
      name: e.name,
      type: e.type,
      description: Map.get(e, :description),
      accept: Map.get(e, :accept, [])
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

  defp map_policy(e) do
    %{
      description: Map.get(e, :description),
      condition: Map.get(e, :condition)
    }
  end
end
