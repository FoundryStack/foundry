defmodule MockResource do
  @moduledoc """
  Minimal Ash.Resource mock for unit tests.
  """
  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule MockPlainModule do
  @moduledoc """
  A plain module with no Spark DSL config (used for negative tests).
  """
  def hello, do: "world"
end
