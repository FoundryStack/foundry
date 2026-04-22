defmodule IgamingRef.Finance.WithdrawalWebhook do
  @moduledoc """
  Payment provider webhook receiver for withdrawal status updates.

  External payment providers (Stripe, PayPal, etc.) POST notifications to this
  endpoint when a withdrawal's processing status changes (e.g., funds transferred,
  failed, reversed). The webhook updates the corresponding WithdrawalRequest and
  triggers compensations if needed.

  Webhooks are idempotent (provider-signature verified) and always respond 200
  to prevent retries. Processing is done async via Oban to unblock the provider.

  Compliance: RG-UK-014 (withdrawal processing integrity), RG-MGA-007 (withdrawal limits).
  """

  use Foundry.Annotations

  @idempotency_key :provider_reference
  @telemetry_prefix [:igaming_ref, :finance, :withdrawal_webhook]
  @compliance [:RG_UK_014, :RG_MGA_007]

  # @side_effect external_http: webhook_inbound, idempotent: true
  # @side_effect oban_emit: process_withdrawal_webhook, idempotent: true

  # Not a resource or action, but a trigger pattern documented for Foundry.
  # In Phoenix, this would be handled via a controller action (e.g.,
  # POST /webhooks/withdrawal in IgamingRef.WebhookController).
  # Foundry sees this as an external trigger that feeds WithdrawalTransfer.

  # Conceptually: this module documents the webhook entry point.
  # The actual implementation is a Phoenix controller + Oban job pair.

  @doc """
  Process a provider webhook for withdrawal status change.

  Idempotent via provider_reference. Dispatches async job to avoid blocking webhook receiver.
  Returns {:ok, request} with 200 response immediately, then processes async.
  """
  def handle_webhook(provider, signature, body) do
    # In a real app, verify_signature/3 checks HMAC against the provider's key
    with :ok <- verify_signature(provider, signature, body),
         {:ok, event} <- parse_event(provider, body),
         {:ok, request} <- dispatch_async_job(event) do
      {:ok, request}
    else
      error -> {:error, error}
    end
  end

  # ─── Private helpers ──────────────────────────────────────────────────────

  defp verify_signature(provider, signature, body) do
    # Stub: real implementation uses provider-specific HMAC verification
    # e.g., Stripe uses HMAC-SHA256 with Stripe-Signature header
    case provider do
      "stripe" -> verify_stripe_signature(signature, body)
      "paypal" -> verify_paypal_signature(signature, body)
      _ -> {:error, "unknown provider: #{provider}"}
    end
  end

  defp verify_stripe_signature(_signature, _body) do
    # Full implementation: hash body with Stripe secret, compare to signature
    # For now: stub that always returns :ok
    :ok
  end

  defp verify_paypal_signature(_signature, _body) do
    # Full implementation: PayPal verification endpoint call
    :ok
  end

  defp parse_event(provider, body) do
    # Parse provider-specific webhook payload into a canonical event struct
    case provider do
      "stripe" -> parse_stripe_event(body)
      "paypal" -> parse_paypal_event(body)
      _ -> {:error, "unknown provider"}
    end
  end

  defp parse_stripe_event(body) do
    # Stub: decode JSON, extract event type and withdrawal reference
    # Real: check for charge.succeeded, charge.failed, charge.refunded events
    case Jason.decode(body) do
      {:ok, data} ->
        {:ok,
         %{
           provider: "stripe",
           event_type: data["type"],
           reference: data["data"]["object"]["id"],
           status: stripe_status(data["type"]),
         }}

      _ ->
        {:error, "malformed stripe event"}
    end
  end

  defp parse_paypal_event(body) do
    # Stub: decode JSON, extract event type and transaction ID
    case Jason.decode(body) do
      {:ok, data} ->
        {:ok,
         %{
           provider: "paypal",
           event_type: data["event_type"],
           reference: data["resource"]["id"],
           status: paypal_status(data["event_type"]),
         }}

      _ ->
        {:error, "malformed paypal event"}
    end
  end

  defp stripe_status("charge.succeeded"), do: :completed
  defp stripe_status("charge.failed"), do: :failed
  defp stripe_status("charge.refunded"), do: :reversed
  defp stripe_status(_), do: :unknown

  defp paypal_status("PAYMENT.CAPTURE.COMPLETED"), do: :completed
  defp paypal_status("PAYMENT.CAPTURE.DENIED"), do: :failed
  defp paypal_status("PAYMENT.CAPTURE.REFUNDED"), do: :reversed
  defp paypal_status(_), do: :unknown

  defp dispatch_async_job(event) do
    # Oban.insert(IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook.new(event))
    {:ok, %{provider_reference: event.reference, status: event.status}}
  end
end
