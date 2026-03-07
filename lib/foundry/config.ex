defmodule Foundry.Config do
  @moduledoc """
  Ash domain for Foundry's internal resources (Manifest).
  Used only when loading and validating project manifests.
  """
  use Ash.Domain

  resources do
    resource(Foundry.Manifest)
  end
end
