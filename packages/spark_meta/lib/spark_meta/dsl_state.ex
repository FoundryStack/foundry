defmodule SparkMeta.DslState do
  @moduledoc """
  Output struct representing the introspected state of a Spark module.

  ## Fields

    * `:module` - The Spark module being introspected (required)
    * `:extensions` - List of extension modules eagerly populated by `walk/1`
    * `:sections` - Map of section paths to lists of structs (lazy, filled by `entities/2`)
    * `:options` - Map of option paths to option dicts (lazy, filled by `get_opt/4`)
    * `:persisted` - Map of persisted values `:extensions` and `:data_layer` eager, rest on-demand
    * `:extension_data` - Map of extension module to extracted data from `SparkMeta.Extension` handlers
  """

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

  @enforce_keys [:module]
  defstruct module: nil,
            extensions: [],
            sections: %{},
            options: %{},
            persisted: %{},
            extension_data: %{},
            moduledoc: nil,
            compliance: [],
            telemetry_prefix: [],
            attributes: [],
            relationships: [],
            actions: [],
            policies: []

  @type t :: %__MODULE__{
          module: atom(),
          extensions: [atom()],
          sections: %{[atom()] => [struct()]},
          options: %{[atom()] => %{atom() => term()}},
          persisted: %{atom() => term()},
          extension_data: %{atom() => term()},
          moduledoc: String.t() | nil,
          compliance: [atom()],
          telemetry_prefix: [atom()],
          attributes: [attribute_map()],
          relationships: [relationship_map()],
          actions: [action_map()],
          policies: [policy_map()]
        }
end
