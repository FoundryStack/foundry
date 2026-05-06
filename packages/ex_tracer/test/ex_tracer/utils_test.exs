defmodule ExTracer.UtilsTest do
  use ExUnit.Case, async: true

  alias ExTracer.Utils

  test "literal_value normalizes aliases, maps, tuples, and keyword lists" do
    ast =
      quote do
        %{module: Demo.Thing, tuple: {:ok, :done}, opts: [mode: :fast]}
      end

    assert Utils.literal_value(ast) == %{
             module: "Demo.Thing",
             tuple: {:ok, :done},
             opts: [mode: :fast]
           }
  end

  test "distinct_consecutive keeps non-adjacent duplicates" do
    assert Utils.distinct_consecutive(["a", "a", "b", "a", "a"]) == ["a", "b", "a"]
  end
end
