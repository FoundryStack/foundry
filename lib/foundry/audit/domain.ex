defmodule Foundry.Audit do
  @moduledoc "Ash domain for Foundry audit resources."
  use Ash.Domain

  resources do
    resource(Foundry.Audit.Event)
  end
end
