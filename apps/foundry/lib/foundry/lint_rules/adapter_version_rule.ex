defmodule Foundry.LintRules.AdapterVersionRule do
  @behaviour Foundry.SparkLint.Rule

  def check(_module, _ctx) do
    # Phase 1: minimal implementation
    # Full implementation in Phase 2+ will check conditional_libraries for unused adapters
    # and verify they are active on ProviderConfig records
    {:ok, []}
  end
end
