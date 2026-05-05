defmodule IgamingRef.Finance.Adapters.StripeAdapter do
  @moduledoc """
  Deterministic reference-project provider adapter for approved withdrawals.

  Returns a stable provider reference so integration scenarios can verify the
  processing-state transition without calling a real network boundary.
  """

  use Foundry.Annotations

  @telemetry_prefix [:igaming_ref, :finance, :stripe_adapter]

  def submit_withdrawal(%{id: request_id, provider: "stripe"}) do
    {:ok,
     %{
       provider: "stripe",
       reference: "stripe-wd-" <> String.slice(request_id, 0, 8),
       status: :accepted
     }}
  end
end
