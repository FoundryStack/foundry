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
    SparkMeta.AshResourceData.extract(module)
  end
end
