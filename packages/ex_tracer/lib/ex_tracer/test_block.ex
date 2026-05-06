defmodule ExTracer.TestBlock do
  @moduledoc false

  @type t :: %__MODULE__{
          name: String.t(),
          kind: :test | :property | String.t(),
          line: pos_integer() | nil,
          block: Macro.t()
        }

  defstruct [:name, :kind, :line, :block]
end
