defmodule IgamingRef.Finance.WithdrawalScenarioTest do
  use ExUnit.Case, async: true
  use Foundry.TestScenario

  describe "RG-UK-014 — Player-triggered withdrawal request enters processing" do
    @scenario category: :compliance,
              compliance_links: ["RG-UK-014"],
              flow: [
                %{
                  id: "start",
                  type: :entry,
                  node: "Finance.WithdrawalTransfer",
                  step_name: "load_request",
                  label: "Start the withdrawal transfer for an approved request",
                  action: "run",
                  actor: "player",
                  emits: ["withdrawal_processing_started"],
                  focus_targets: ["Finance.Rules.WithdrawalLimitNotExceeded"]
                },
                %{
                  id: "guard",
                  type: :command,
                  node: "Finance.Rules.WithdrawalLimitNotExceeded",
                  reacts_to: "withdrawal_processing_started",
                  label: "Confirm the withdrawal stays within the player daily limit",
                  details:
                    "WithdrawalTransfer also runs self-exclusion, KYC, and sufficient-balance guards before any funds move.",
                  focus_targets: ["Finance.Wallet"]
                },
                %{
                  id: "debit",
                  type: :reaction,
                  node: "Finance.Wallet",
                  label: "Debit the wallet once the withdrawal guards pass",
                  emits: ["wallet_debited_for_withdrawal"],
                  focus_targets: ["Finance.WithdrawalTransfer:step:4"]
                },
                %{
                  id: "ledger",
                  type: :reaction,
                  node: "Finance.LedgerEntry",
                  reacts_to: "wallet_debited_for_withdrawal",
                  label: "Record the immutable withdrawal ledger entry",
                  emits: ["withdrawal_ledger_recorded"],
                  focus_targets: ["Finance.WithdrawalRequest"]
                },
                %{
                  id: "mark_processing",
                  type: :assertion,
                  node: "Finance.WithdrawalRequest",
                  graph_node: "Finance.WithdrawalTransfer:step:6",
                  reacts_to: "withdrawal_ledger_recorded",
                  label: "Mark the withdrawal request as processing with the provider reference",
                  details: "The request state changes only after provider submission succeeds."
                }
              ]

    test "shows the approved withdrawal processing trace" do
      :ok
    end
  end

  describe "Provider posts withdrawal status webhook" do
    @scenario category: :compliance,
              compliance_links: ["RG-UK-014", "RG-MGA-007"],
              flow: [
                %{
                  id: "receive_webhook",
                  type: :entry,
                  node: "Finance.WithdrawalWebhook",
                  label: "Validate the provider signature and normalize the webhook payload",
                  action: "handle_webhook",
                  actor: "provider",
                  emits: ["withdrawal_webhook_normalized"],
                  focus_targets: ["Finance.WithdrawalWebhookEvent"]
                },
                %{
                  id: "persist_webhook_event",
                  type: :reaction,
                  node: "Finance.WithdrawalWebhookEvent",
                  reacts_to: "withdrawal_webhook_normalized",
                  label: "Persist the normalized webhook event with receive action",
                  emits: ["withdrawal_webhook_received"],
                  focus_targets: ["Finance.Jobs.ProcessWithdrawalWebhook"]
                },
                %{
                  id: "enqueue_processing",
                  type: :event,
                  node: "Finance.WithdrawalWebhook",
                  reacts_to: "withdrawal_webhook_received",
                  label: "Enqueue the Oban processor job without blocking the provider",
                  emits: ["withdrawal_webhook_job_enqueued"],
                  focus_targets: ["Finance.Jobs.ProcessWithdrawalWebhook"]
                },
                %{
                  id: "apply_status",
                  type: :job,
                  node: "Finance.Jobs.ProcessWithdrawalWebhook",
                  reacts_to: "withdrawal_webhook_job_enqueued",
                  label:
                    "Load the matching withdrawal request and apply the provider status transition",
                  focus_targets: ["Finance.WithdrawalRequest"]
                },
                %{
                  id: "request_updated",
                  type: :assertion,
                  node: "Finance.WithdrawalRequest",
                  label: "Persist the updated withdrawal request status from the webhook worker"
                }
              ]

    test "shows the webhook ingestion trace" do
      :ok
    end
  end

  describe "Oban worker applies withdrawal webhook status" do
    @scenario category: :invariant,
              flow: [
                %{
                  id: "job_start",
                  type: :entry,
                  node: "Finance.Jobs.ProcessWithdrawalWebhook",
                  label: "Start the queued webhook processing job",
                  action: "perform",
                  actor: "oban",
                  emits: ["withdrawal_webhook_job_started"],
                  focus_targets: ["Finance.WithdrawalWebhookEvent"]
                },
                %{
                  id: "load_event",
                  type: :reaction,
                  node: "Finance.WithdrawalWebhookEvent",
                  reacts_to: "withdrawal_webhook_job_started",
                  label: "Use the provider reference to locate the persisted webhook event",
                  emits: ["withdrawal_webhook_event_loaded"],
                  focus_targets: ["Finance.WithdrawalRequest"]
                },
                %{
                  id: "transition_request",
                  type: :assertion,
                  node: "Finance.WithdrawalRequest",
                  reacts_to: "withdrawal_webhook_event_loaded",
                  label: "Apply the provider-driven status transition to the withdrawal request",
                  details:
                    "The worker is the async boundary between webhook receipt and request state change."
                }
              ]

    test "shows the oban processing trace" do
      :ok
    end
  end
end

defmodule IgamingRef.Promotions.BonusScenarioTest do
  use ExUnit.Case, async: true
  use Foundry.TestScenario

  describe "Bonus event ingestion drives evaluation and grant execution" do
    @scenario category: :property,
              compliance_links: ["RG-MGA-005", "RG-UK-011"],
              flow: [
                %{
                  id: "ingest_bonus_event",
                  type: :entry,
                  node: "Promotions.BonusEvent",
                  label: "Persist the inbound bonus event that will drive campaign evaluation",
                  action: "bonus_event_received",
                  actor: "system",
                  emits: ["bonus_event_ingested"],
                  focus_targets: ["Promotions.BonusEvaluationReactor"]
                },
                %{
                  id: "evaluate_bonus_event",
                  type: :reaction,
                  node: "Promotions.BonusEvaluationReactor",
                  step_name: "find_matching_campaigns",
                  reacts_to: "bonus_event_ingested",
                  label: "Load the event, player, and active campaigns to find eligible matches",
                  emits: ["bonus_event_matched"],
                  focus_targets: ["Promotions.BonusCampaign"]
                },
                %{
                  id: "select_campaign",
                  type: :command,
                  node: "Promotions.BonusCampaign",
                  reacts_to: "bonus_event_matched",
                  label:
                    "Use active campaign configuration as the source of bonus execution rules",
                  focus_targets: ["Promotions.BonusGrantTransfer:step:4"],
                  details:
                    "Matching triggers, condition groups, and executions stay data-driven on the campaign."
                },
                %{
                  id: "grant_bonus",
                  type: :reaction,
                  node: "Promotions.BonusGrantTransfer",
                  step_name: "create_bonus_grant",
                  label: "Run the whitelisted bonus grant transfer for the matched campaign",
                  emits: ["bonus_granted"],
                  focus_targets: ["Promotions.BonusGrant"]
                },
                %{
                  id: "persist_grant",
                  type: :assertion,
                  node: "Promotions.BonusGrant",
                  reacts_to: "bonus_granted",
                  label: "Persist the player bonus grant and its wagering state"
                }
              ]

    test "shows the bonus event runtime trace" do
      :ok
    end
  end
end
