defmodule Foundry.Proposals do
  @moduledoc "Ash domain for Foundry proposal resources."
  use Ash.Domain

  resources do
    resource(Foundry.Proposals.Proposal)
  end
end
