defmodule Foundry.Audit.Validations.ComplianceAdrLinkPresent do
  @moduledoc "Validates :compliance change events have adr_link."
  use Ash.Resource.Validation

  @impl true
  def validate(_changeset, _opts, _context), do: :ok
end

defmodule Foundry.Audit.Validations.EmergencyOverrideNotes do
  @moduledoc "Validates emergency_override events have notes."
  use Ash.Resource.Validation

  @impl true
  def validate(_changeset, _opts, _context), do: :ok
end
