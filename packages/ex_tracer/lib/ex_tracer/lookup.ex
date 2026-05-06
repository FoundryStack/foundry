defmodule ExTracer.Lookup do
  @moduledoc false

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
