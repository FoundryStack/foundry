defmodule IgamingRef.Ops do
  @moduledoc """
  Ops domain: handles audit trails and PII management.

  Resources:
    - AuditEntry
    - PIIVault
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain, AshPaperTrail.Domain],
    validate_config_inclusion?: false

  resources do
    resource IgamingRef.Ops.AuditEntry
    resource IgamingRef.Ops.PIIVault
  end
end
