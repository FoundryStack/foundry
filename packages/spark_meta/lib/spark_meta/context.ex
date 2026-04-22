defmodule SparkMeta.Context do
  @moduledoc """
  Pipeline context for SparkMeta analysis passes.

  Carries the target module, the loaded DSL state when available, optional
  source material, and any diagnostics discovered while building the context.
  """

  @enforce_keys [:module]
  defstruct [
    :module,
    spark_module?: false,
    dsl_state: nil,
    source_path: nil,
    source_text: nil,
    source_ast: nil,
    diagnostics: []
  ]

  @type diagnostic :: map()

  @type t :: %__MODULE__{
          module: module(),
          spark_module?: boolean(),
          dsl_state: SparkMeta.DslState.t() | nil,
          source_path: String.t() | nil,
          source_text: String.t() | nil,
          source_ast: Macro.t() | nil,
          diagnostics: [diagnostic()]
        }
end
