defmodule Foundry.Context.ScenarioExtractor do
  @moduledoc """
  Extracts Studio scenarios from executable test source.

  Real test and property bodies are the source of truth. `@scenario` metadata is
  optional and may refine category, compliance links, labels, or graph focus for
  traced steps, but it never creates a scenario on its own.
  """

  alias Foundry.Context.Scenarios.Extractor

  defdelegate extract(project_root, nodes), to: Extractor
end
