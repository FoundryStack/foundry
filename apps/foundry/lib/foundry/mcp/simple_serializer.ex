defmodule Foundry.MCP.SimpleSerializer do
  @moduledoc """
  Custom AshJsonApi serializer for Ash.DataLayer.Simple resources.

  Handles serialization of Simple data layer records that AshJsonApi
  doesn't natively support.
  """

  def serialize_record(record, _resource, _opts) do
    record
    |> Map.from_struct()
    |> clean_metadata()
  end

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
