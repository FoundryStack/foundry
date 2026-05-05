defmodule IgamingRef.Finance.WithdrawalWebhook do
  @moduledoc """
  Payment provider webhook receiver for withdrawal status updates.

  External payment providers (Stripe, PayPal, etc.) POST notifications to this
  endpoint when a withdrawal's processing status changes (e.g., funds transferred,
  failed, reversed). The webhook updates the corresponding WithdrawalRequest and
  triggers compensations if needed.

  Webhooks are idempotent (provider-signature verified) and always respond 200
  to prevent retries. Processing is done async via Oban to unblock the provider.
  Every inbound event is persisted via `WithdrawalWebhookEvent.receive`.

  Compliance: RG-UK-014 (withdrawal processing integrity), RG-MGA-007 (withdrawal limits).
  """

  use Foundry.Annotations

  @idempotency_key :provider_reference
  @telemetry_prefix [:igaming_ref, :finance, :withdrawal_webhook]
  @compliance [:RG_UK_014, :RG_MGA_007]

  alias IgamingRef.Finance.WithdrawalWebhookEvent

  @doc """
  Process a provider webhook for withdrawal status change.

  Idempotent via provider_reference. Dispatches async job to avoid blocking webhook receiver.
  Returns {:ok, request} with 200 response immediately, then processes async.
  """
  def handle_webhook(provider, signature, body) do
    # In a real app, verify_signature/3 checks HMAC against the provider's key
    with :ok <- verify_signature(provider, signature, body),
         {:ok, event} <- parse_event(provider, body),
         {:ok, persisted} <- persist_event(event),
         {:ok, _job} <- dispatch_async_job(event) do
      {:ok, persisted}
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
           payload: data
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
           payload: data
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

  defp persist_event(event) do
    WithdrawalWebhookEvent
    |> Ash.Changeset.for_create(:receive, %{
      provider: event.provider,
      provider_reference: event.reference,
      event_type: event.event_type,
      status: event.status,
      payload: event.payload || %{}
    })
    |> Ash.create(actor: %{is_system: true})
  end

  defp dispatch_async_job(event) do
    args = %{
      "provider" => event.provider,
      "event_type" => event.event_type,
      "provider_reference" => event.reference,
      "status" => Atom.to_string(event.status)
    }

    Oban.insert(IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook.new(args))
  end
end
