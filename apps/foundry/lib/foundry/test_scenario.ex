defmodule Foundry.TestScenario do
  @moduledoc """
  Lightweight test-side annotations for Studio scenario extraction.

  `@scenario` is intentionally small. Real executable test calls remain the
  primary source of truth; the attribute only adds labels or exact-focus hints
  where code alone is ambiguous.

  Example:

      use Foundry.TestScenario

      @scenario category: :compliance,
                compliance_links: ["RG-UK-014"],
                flow: [
                  %{
                    id: "receive",
                    type: :entry,
                    node: "Finance.WithdrawalWebhook",
                    label: "Validate webhook payload",
                    action: "handle_webhook",
                    focus_targets: ["Finance.WithdrawalWebhookEvent"]
                  }
                ]
  """

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :scenario, accumulate: true, persist: true)
    end
  end
end
