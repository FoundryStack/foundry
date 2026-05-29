defmodule Foundry.MCP.ToolSerializer do
  @moduledoc """
  Post-processes MCP tool results to properly serialize Simple resources.

  AshJsonApi doesn't serialize Simple data layer resources, so we intercept
  the result and convert structs to maps before JSON encoding.
  """

  def serialize_tool_result({:ok, records}) when is_list(records) do
    {:ok, Enum.map(records, &serialize_record/1)}
  end

  def serialize_tool_result({:ok, record}) do
    {:ok, serialize_record(record)}
  end

  def serialize_tool_result(error), do: error

  defp serialize_record(nil), do: nil

  defp serialize_record(record) when is_struct(record) do
    record
    |> Map.from_struct()
    |> clean_metadata()
  end

  defp serialize_record(map) when is_map(map) do
    clean_metadata(map)
  end

  defp serialize_record(other), do: other

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
