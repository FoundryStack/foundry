defmodule IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook do
  @moduledoc """
  Processes provider webhook events for withdrawal status updates.

  Runs asynchronously after the webhook receiver has validated the signature and
  normalized the payload. The worker loads the matching WithdrawalRequest and
  applies the provider status transition.
  """

  use Foundry.Annotations

  use Oban.Worker, queue: :default, max_attempts: 5

  @performs IgamingRef.Finance.WithdrawalRequest

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"provider_reference" => _provider_reference, "status" => _status}
      }) do
    # In production this would load the matching request and update its status.
    :ok
  end
end
