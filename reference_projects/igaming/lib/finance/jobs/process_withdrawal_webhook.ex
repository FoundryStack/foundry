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
  def perform(%Oban.Job{args: %{"provider_reference" => _provider_reference, "status" => _status}}) do
    Foundry.TestScenario.trace_node("IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook", %{
      type: :entry,
      kind: :job_execute,
      label: "Execute ProcessWithdrawalWebhook.perform/1",
      module_function: "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook.perform",
      source_snippet: "perform(%Oban.Job{...})",
      details: "Job implementation is currently stubbed."
    })

    # In production this would load the matching request and update its status.
    :ok
  end
end
