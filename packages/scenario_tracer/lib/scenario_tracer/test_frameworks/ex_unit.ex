defmodule ScenarioTracer.TestFrameworks.ExUnit do
  @behaviour ExTracer.TestFramework

  def block_patterns, do: [{:test, 2}, {:test, 3}, {:property, 2}, {:property, 3}]
  def metadata_attrs, do: [:scenario, :tag, :moduletag]
  def test_kinds, do: %{test: :test, property: :property}
end
