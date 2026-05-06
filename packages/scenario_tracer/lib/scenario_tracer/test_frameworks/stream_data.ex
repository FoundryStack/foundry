defmodule ScenarioTracer.TestFrameworks.StreamData do
  @behaviour ExTracer.TestFramework

  def block_patterns, do: [{:property, 2}, {:property, 3}]
  def metadata_attrs, do: [:scenario, :tag, :moduletag]
  def test_kinds, do: %{property: :property}
end
