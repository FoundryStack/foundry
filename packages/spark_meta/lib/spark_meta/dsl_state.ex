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

  @enforce_keys [:module]
  defstruct module: nil,
            extensions: [],
            sections: %{},
            options: %{},
            persisted: %{},
            extension_data: %{}

  @type t :: %__MODULE__{
          module: atom(),
          extensions: [atom()],
          sections: %{[atom()] => [struct()]},
          options: %{[atom()] => %{atom() => term()}},
          persisted: %{atom() => term()},
          extension_data: %{atom() => term()}
        }
end
