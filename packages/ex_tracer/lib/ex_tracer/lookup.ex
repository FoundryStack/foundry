defmodule ExTracer.Lookup do
  @moduledoc """
  Cross-reference index linking steps to code, graph nodes, and runtime traces.

  Built once from code-loaded modules and passed through the analysis pipeline,
  Lookup enables adapters to:
  - Resolve function calls to their source AST and modules (`:code`)
  - Map calls to domain graph nodes (`:by_id`)
  - Match executed test steps against recorded traces (`:runtime`)
  - Resolve module aliases (`:aliases`)

  Constructed by the application calling the extraction pipeline.
  See `ScenarioTracer.MixTask` for an example builder.
  """

  alias ExTracer.RuntimeTrace

  @type code_entry :: %{
          ast: Macro.t(),
          alias_map: map(),
          file: String.t(),
          source: String.t()
        }

  @type t :: %__MODULE__{
          by_id: map(),
          aliases: map(),
          code: %{optional(String.t()) => code_entry()},
          runtime: %{optional(String.t()) => [RuntimeTrace.t()]}
        }

  defstruct by_id: %{}, aliases: %{}, code: %{}, runtime: %{}
end
