defmodule MockResource do
  @moduledoc """
  Minimal Ash.Resource mock for unit tests.
  """
  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule MockResourceWithDocs do
  @moduledoc "A mock resource with rich documentation for testing."

  # Note: @compliance and @telemetry_prefix are not set here because Elixir only keeps
  # module attributes in the BEAM if they are referenced/used. Integration tests verify
  # these work on real resources that do reference them.

  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      description("The name of the resource.")
      allow_nil?(false)
    end

    attribute :status, :atom do
      description("Current status.")
      default(:active)
      allow_nil?(false)
    end
  end

  relationships do
    belongs_to :owner, MockResource do
      description("The owning resource.")
      allow_nil?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      description("Create a new mock.")
      accept([:name])
    end
  end
end

defmodule MockPlainModule do
  @moduledoc """
  A plain module with no Spark DSL config (used for negative tests).
  """
  def hello, do: "world"
end
