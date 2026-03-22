defmodule Foundry.LintRules.Registry do
  @moduledoc """
  Explicit registry of all active lint rules.
  Adding a new Foundry.LintRules.* module requires adding it here.
  Accidental registration is worse than a deliberate omission.
  """

  @module_rules [
    Foundry.LintRules.PaperTrailRule,
    Foundry.LintRules.ArchivalRule,
    Foundry.LintRules.RunbookRule,
    Foundry.LintRules.IdempotencyRule,
    Foundry.LintRules.DescriptionRule,
    Foundry.LintRules.VersionRule,
    Foundry.LintRules.AdapterVersionRule
  ]

  def module_rules, do: @module_rules
  def manifest_validators, do: [Foundry.LintRules.ManifestValidator]
end
