defmodule IgamingRef.Finance.Adapters.PaypalAdapter do
  @moduledoc """
  Deterministic reference-project PayPal adapter for approved withdrawals.

  The adapter is intentionally local-only and exists so end-to-end scenario
  tests can execute the provider submission boundary without mocks.
  """

  use Foundry.Annotations

  @telemetry_prefix [:igaming_ref, :finance, :paypal_adapter]

  def submit_withdrawal(%{id: request_id, provider: "paypal"}) do
    {:ok,
     %{
       provider: "paypal",
       reference: "paypal-wd-" <> String.slice(request_id, 0, 8),
       status: :accepted
     }}
  end
end
