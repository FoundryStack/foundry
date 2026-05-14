defmodule AshSDUI.TestHelper do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case, async: true
    end
  end
end
