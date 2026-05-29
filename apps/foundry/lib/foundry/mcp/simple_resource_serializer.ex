defmodule Foundry.MCP.SimpleResourceSerializer do
  @moduledoc """
  Custom AshJsonApi serializer for Ash Simple data layer resources.

  AshJsonApi.Serializers doesn't have a handler for Simple data layer,
  so this serializer converts Simple resource structs to serializable maps.
  """

  defstruct [:data, :included, :errors]

  def serialize(records, resource, opts) when is_list(records) do
    data = Enum.map(records, &serialize_record(&1, resource, opts))
    %__MODULE__{data: data, included: [], errors: nil}
  end

  def serialize(record, resource, opts) do
    data = serialize_record(record, resource, opts)
    %__MODULE__{data: [data], included: [], errors: nil}
  end

  defp serialize_record(nil, _resource, _opts), do: nil

  defp serialize_record(record, _resource, _opts) when is_struct(record) do
    record
    |> Map.from_struct()
    |> clean_metadata()
  end

  defp serialize_record(record, _resource, _opts) when is_map(record) do
    clean_metadata(record)
  end

  defp serialize_record(other, _resource, _opts), do: other

  defp clean_metadata(map) do
    Map.drop(map, [
      :__meta__,
      :__metadata__,
      :__lateral_join_source__,
      :__order__,
      :aggregates,
      :calculations
    ])
  end
end
