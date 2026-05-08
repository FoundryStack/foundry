defmodule Foundry.Context.ScenarioExtractorTest do
  use ExUnit.Case, async: false

  alias Foundry.Context.NodeEntry
  alias Foundry.Context.ScenarioExtractor

  describe "extract/2" do
    test "returns empty list when test directory does not exist" do
      assert ScenarioExtractor.extract("/nonexistent/path", []) == []
    end

    test "ignores placeholder-only scenarios with no traceable executable calls" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "placeholder_scenario.exs",
        """
        defmodule IgamingRef.Finance.PlaceholderScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          describe "placeholder" do
            @scenario category: :compliance,
                      compliance_links: ["RG-UK-014"],
                      flow: [
                        %{label: "This should not count", node: "Finance.WithdrawalWebhook"}
                      ]

            test "still a stub" do
              :ok
            end
          end
        end
        """
      )

      assert ScenarioExtractor.extract(tmpdir, [
               node("IgamingRef.Finance.WithdrawalWebhook", "trigger")
             ]) == []
    end

    test "expands webhook failure traces with provenance and short-circuit semantics" do
      tmpdir = tmp_project_root()

      write_lib_file(
        tmpdir,
        "finance/withdrawal_webhook.ex",
        """
        defmodule IgamingRef.Finance.WithdrawalWebhook do
          alias IgamingRef.Finance.WithdrawalWebhookEvent
          alias IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook

          def handle_webhook(provider, signature, body) do
            with :ok <- verify_signature(provider, signature, body),
                 {:ok, event} <- parse_event(provider, body),
                 {:ok, persisted} <- persist_event(event),
                 {:ok, _job} <- dispatch_async_job(event) do
              {:ok, persisted}
            else
              error -> {:error, error}
            end
          end

          defp verify_signature(provider, _signature, _body) do
            case provider do
              "stripe" -> :ok
              _ -> {:error, "unknown provider: \#{provider}"}
            end
          end

          defp parse_event(_provider, _body), do: {:ok, %{reference: "wh_123"}}
          defp persist_event(_event), do: {:ok, %{id: "evt_1", module: WithdrawalWebhookEvent}}
          defp dispatch_async_job(_event), do: {:ok, %{module: ProcessWithdrawalWebhook}}
        end

        defmodule IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook do
          def perform(_job), do: :ok
        end

        defmodule IgamingRef.Finance.WithdrawalWebhookEvent do
        end
        """
      )

      write_test_file(
        tmpdir,
        "withdrawal_webhook_scenario.exs",
        """
        defmodule IgamingRef.Finance.WithdrawalWebhookScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Finance.WithdrawalWebhook

          describe "Webhook processing flow" do
            @scenario category: :compliance, compliance_links: ["RG-UK-014"]

            test "rejects unknown providers before persistence" do
              assert {:error, {:error, "unknown provider: unknown"}} =
                       WithdrawalWebhook.handle_webhook("unknown", "sig", "{}")
            end
          end
        end
        """
      )

      nodes = [
        node("IgamingRef.Finance.WithdrawalWebhook", "trigger"),
        node("IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook", "job"),
        node("IgamingRef.Finance.WithdrawalWebhookEvent", "resource")
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)
      assert scenario.category == :compliance
      assert scenario.level == :webhook
      assert scenario.evidence_summary.executed_steps >= 1
      assert scenario.evidence_summary.expanded_steps >= 1
      assert scenario.evidence_summary.branch_steps >= 1

      assert Enum.any?(
               scenario.flow,
               &(&1.provenance == :executed and &1.kind == :trigger_receive)
             )

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and step.label == "Verify provider signature" and
                 step.status == :short_circuit
             end)

      refute Enum.any?(scenario.flow, &(&1.provenance == :expanded and &1.kind == :write))

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :branch and String.contains?(step.label, "failure")
             end)
    end

    test "expands rule calls into branch-level detail from source code" do
      tmpdir = tmp_project_root()

      write_lib_file(
        tmpdir,
        "rules.ex",
        """
        defmodule IgamingRef.Promotions.Rules.PlayerEligibleForCampaign do
          def evaluate(%{player: player, campaign: campaign, existing_grants: existing_grants} = context, _ctx) do
            player_grants =
              Enum.filter(existing_grants, &(&1.player_id == player.id and &1.campaign_id == campaign.id))

            campaign_grants = Map.get(context, :campaign_grants, existing_grants)

            cond do
              player.status != :active ->
                {:error, :player_not_active, "inactive"}

              campaign.max_redemptions != nil and length(campaign_grants) >= campaign.max_redemptions ->
                {:error, :campaign_max_redemptions_reached, "limit reached"}

              Enum.any?(player_grants, &(&1.status == :active)) ->
                {:error, :player_already_has_grant, "active grant"}

              true ->
                :ok
            end
          end
        end
        """
      )

      write_test_file(
        tmpdir,
        "campaign_rule_test.exs",
        """
        defmodule IgamingRef.Promotions.CampaignRuleScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Promotions.Rules.PlayerEligibleForCampaign

          describe "PlayerEligibleForCampaign" do
            @scenario category: :invariant

            test "rejects when campaign max_redemptions reached" do
              player = %{id: "player-1", status: :active}
              campaign = %{id: "camp-1", max_redemptions: 1}
              grants = []
              campaign_grants = [%{player_id: "another", campaign_id: "camp-1", status: :active}]

              assert {:error, :campaign_max_redemptions_reached, _} =
                       PlayerEligibleForCampaign.evaluate(
                         %{player: player, campaign: campaign, existing_grants: grants, campaign_grants: campaign_grants},
                         nil
                       )
            end
          end
        end
        """
      )

      [scenario] =
        ScenarioExtractor.extract(tmpdir, [
          node("IgamingRef.Promotions.Rules.PlayerEligibleForCampaign", "rule")
        ])

      assert scenario.level == :rule

      assert Enum.any?(scenario.flow, &(&1.provenance == :executed and &1.kind == :rule_check))

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and step.label == "Resolve campaign grant set"
             end)

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :branch and
                 String.contains?(step.label, "campaign.max redemptions")
             end)

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :branch and
                 String.contains?(step.result || "", ":campaign_max_redemptions_reached")
             end)
    end

    test "infers piped Ash.Changeset calls as executable action preparation steps" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "piped_changeset_scenario.exs",
        """
        defmodule IgamingRef.Finance.PipedChangesetScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Finance.WithdrawalRequest

          describe "Piped changeset flow" do
            @scenario category: :compliance

            test "prepares an approval changeset through a pipeline" do
              %{}
              |> Ash.Changeset.for_update(WithdrawalRequest, :approve, %{provider: "stripe"})

              assert true
            end
          end
        end
        """
      )

      nodes = [
        %NodeEntry{
          id: "IgamingRef.Finance.WithdrawalRequest",
          module: "IgamingRef.Finance.WithdrawalRequest",
          type: "resource",
          domain: "Finance",
          description: "Withdrawal request",
          actions: [%{name: "approve", type: "update"}]
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :executed and
                 step.kind == :action_prepare and
                 step.node_id == "IgamingRef.Finance.WithdrawalRequest" and
                 step.action == "approve"
             end)
    end

    test "keeps repeated calls separate when they hit different rule branches" do
      tmpdir = tmp_project_root()

      write_lib_file(
        tmpdir,
        "rules.ex",
        """
        defmodule IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded do
          def evaluate(%{player: player, amount: amount, daily_used: daily_used}, _ctx) do
            limit = Map.get(%{low: 1000, high: 500}, player.risk_level, 1000)
            total = daily_used + amount

            case total > limit do
              true -> {:error, :daily_limit_exceeded, "too much"}
              false -> :ok
            end
          end
        end
        """
      )

      write_test_file(
        tmpdir,
        "limit_rule_test.exs",
        """
        defmodule IgamingRef.Finance.LimitRuleScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded

          describe "WithdrawalLimitNotExceeded" do
            @scenario category: :invariant

            test "rejects over limit" do
              assert {:error, :daily_limit_exceeded, _} =
                       WithdrawalLimitNotExceeded.evaluate(%{player: %{risk_level: :high}, amount: 400, daily_used: 200}, nil)
            end

            test "passes within limit" do
              assert :ok =
                       WithdrawalLimitNotExceeded.evaluate(%{player: %{risk_level: :low}, amount: 100, daily_used: 100}, nil)
            end
          end
        end
        """
      )

      [scenario] =
        ScenarioExtractor.extract(tmpdir, [
          node("IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded", "rule")
        ])

      matched_results =
        scenario.flow
        |> Enum.filter(&(&1.provenance == :branch and &1.kind == :assert_result))
        |> Enum.map(& &1.result)

      assert Enum.any?(matched_results, &String.contains?(&1, ":daily_limit_exceeded"))
      assert Enum.any?(matched_results, &(&1 == ":ok"))
      assert scenario.level == :rule
      assert scenario.nodes == ["IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded"]
      assert scenario.graph_path == ["IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded"]
    end

    test "renders Ash.Changeset.for_create as preparation only" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "bonus_event_changeset_test.exs",
        """
        defmodule IgamingRef.Promotions.BonusEventChangesetScenarioTest do
          use ExUnit.Case, async: true

          alias IgamingRef.Promotions.BonusEvent

          describe "Bonus event changeset is built" do
            test "prepares the ingest action" do
              assert %{} =
                       Ash.Changeset.for_create(BonusEvent, :ingest, %{kind: :deposit_completed})
            end
          end
        end
        """
      )

      nodes = [
        %NodeEntry{
          id: "IgamingRef.Promotions.BonusEvent",
          module: "IgamingRef.Promotions.BonusEvent",
          type: "resource",
          domain: "Promotions",
          description: "Bonus event",
          actions: [%{name: "ingest", type: "create", description: "Persist event"}]
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)
      assert scenario
      assert scenario.level == :action
      [first_step | _] = scenario.flow

      assert first_step.kind == :action_prepare
      assert first_step.provenance == :executed
      assert first_step.details == "Only action preparation executed"
      assert scenario.nodes == ["IgamingRef.Promotions.BonusEvent"]
      assert scenario.graph_path == ["IgamingRef.Promotions.BonusEvent:action:ingest"]

      refute Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and
                 String.starts_with?(step.label || "", "Execute BonusEvent")
             end)
    end

    test "maps Reactor.run entrypoints to transfer and reactor scenario coverage" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "pipeline_focus_scenario.exs",
        """
        defmodule IgamingRef.Promotions.BonusFocusScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Promotions.BonusEvaluationReactor
          alias IgamingRef.Promotions.BonusGrantTransfer

          describe "Bonus focus flow" do
            @scenario category: :property

            test "focuses exact graph steps" do
              assert {:error, _} =
                       Reactor.run(BonusEvaluationReactor, %{event_id: "evt-1", actor: :system})

              assert {:error, _} =
                       Reactor.run(BonusGrantTransfer, %{player_id: "player-1", campaign_id: "camp-1", actor: :system})
            end
          end
        end
        """
      )

      nodes = [
        %NodeEntry{
          id: "IgamingRef.Promotions.BonusEvaluationReactor",
          module: "IgamingRef.Promotions.BonusEvaluationReactor",
          type: "reactor",
          domain: "Promotions",
          description: "Bonus evaluation reactor",
          steps: [
            %{
              name: "load_event",
              step_index: 0,
              description: "Load event",
              target_resource: "IgamingRef.Promotions.BonusEvent",
              step_kind: :read
            },
            %{
              name: "load_player",
              step_index: 1,
              description: "Load player",
              target_resource: "IgamingRef.Players.Player",
              step_kind: :read
            }
          ]
        },
        %NodeEntry{
          id: "IgamingRef.Promotions.BonusGrantTransfer",
          module: "IgamingRef.Promotions.BonusGrantTransfer",
          type: "transfer",
          domain: "Promotions",
          description: "Bonus grant transfer",
          steps: [
            %{
              name: "load_context",
              step_index: 0,
              description: "Load context",
              target_resource: "IgamingRef.Players.Player",
              step_kind: :read
            },
            %{
              name: "create_bonus_grant",
              step_index: 1,
              description: "Create grant",
              target_resource: "IgamingRef.Promotions.BonusGrant",
              step_kind: :write
            }
          ]
        },
        node("IgamingRef.Promotions.BonusEvent", "resource"),
        node("IgamingRef.Players.Player", "resource"),
        node("IgamingRef.Promotions.BonusGrant", "resource")
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)
      assert scenario.level == :transfer

      assert Enum.count(Enum.filter(scenario.flow, &(&1.provenance == :executed))) == 2

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and step.label == "Load event" and
                 step.focus_node_id == "IgamingRef.Promotions.BonusEvaluationReactor:step:0"
             end)

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and step.label == "Create grant" and
                 step.focus_node_id == "IgamingRef.Promotions.BonusGrantTransfer:step:1"
             end)

      assert scenario.nodes == [
               "IgamingRef.Promotions.BonusEvaluationReactor",
               "IgamingRef.Promotions.BonusEvent",
               "IgamingRef.Players.Player",
               "IgamingRef.Promotions.BonusGrantTransfer",
               "IgamingRef.Promotions.BonusGrant"
             ]

      assert scenario.graph_path == [
               "IgamingRef.Promotions.BonusEvaluationReactor",
               "IgamingRef.Promotions.BonusEvaluationReactor:step:0",
               "IgamingRef.Promotions.BonusEvaluationReactor:step:1",
               "IgamingRef.Promotions.BonusEvaluationReactor",
               "IgamingRef.Promotions.BonusGrantTransfer",
               "IgamingRef.Promotions.BonusGrantTransfer:step:0",
               "IgamingRef.Promotions.BonusGrantTransfer:step:1",
               "IgamingRef.Promotions.BonusGrantTransfer"
             ]
    end

    test "prefers runtime traces for overlay coverage when scenario trace artifacts exist" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "runtime_webhook_scenario.exs",
        """
        defmodule IgamingRef.Finance.RuntimeWebhookScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Finance.WithdrawalWebhook

          describe "Runtime-backed webhook flow" do
            @scenario category: :compliance

            test "executes the webhook entrypoint" do
              assert {:error, _} = WithdrawalWebhook.handle_webhook("stripe", "sig", "{}")
            end
          end
        end
        """
      )

      write_trace_file(
        tmpdir,
        "runtime_webhook_trace.json",
        %{
          "scenario_id" =>
            "IgamingRef.Finance.RuntimeWebhookScenarioTest.runtime_backed_webhook_flow",
          "test_name" => "Runtime-backed webhook flow executes the webhook entrypoint",
          "events" => [
            %{
              "type" => "entry",
              "kind" => "trigger_receive",
              "label" => "Receive provider withdrawal webhook",
              "node_id" => "IgamingRef.Finance.WithdrawalWebhook",
              "focus_node_id" => "IgamingRef.Finance.WithdrawalWebhook"
            },
            %{
              "type" => "reaction",
              "kind" => "action_execute",
              "label" => "Invoke WithdrawalWebhookEvent.receive",
              "node_id" => "IgamingRef.Finance.WithdrawalWebhookEvent",
              "focus_node_id" => "IgamingRef.Finance.WithdrawalWebhookEvent:action:receive",
              "action" => "receive"
            },
            %{
              "type" => "reaction",
              "kind" => "job_enqueue",
              "label" => "Enqueue ProcessWithdrawalWebhook job",
              "node_id" => "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook",
              "focus_node_id" => "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook"
            }
          ]
        }
      )

      nodes = [
        node("IgamingRef.Finance.WithdrawalWebhook", "trigger"),
        %NodeEntry{
          id: "IgamingRef.Finance.WithdrawalWebhookEvent",
          module: "IgamingRef.Finance.WithdrawalWebhookEvent",
          type: "resource",
          domain: "Finance",
          description: "Webhook event",
          actions: [%{name: "receive", type: "create"}]
        },
        node("IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook", "job")
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert scenario.evidence_mode == :runtime
      assert scenario.trace_status == :present

      assert scenario.nodes == [
               "IgamingRef.Finance.WithdrawalWebhook",
               "IgamingRef.Finance.WithdrawalWebhookEvent",
               "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook"
             ]

      assert Enum.take(scenario.graph_path, 3) == [
               "IgamingRef.Finance.WithdrawalWebhook",
               "IgamingRef.Finance.WithdrawalWebhookEvent:action:receive",
               "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook"
             ]
    end

    test "expands automatic runtime entrypoints through the graph without manual trace boilerplate" do
      tmpdir = tmp_project_root()

      write_lib_file(
        tmpdir,
        "finance/withdrawal_webhook.ex",
        """
        defmodule IgamingRef.Finance.WithdrawalWebhook do
          alias IgamingRef.Finance.WithdrawalWebhookEvent
          alias IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook

          def handle_webhook(provider, signature, body) do
            with :ok <- verify_signature(provider, signature, body),
                 {:ok, event} <- parse_event(provider, body),
                 {:ok, persisted} <- persist_event(event),
                 {:ok, _job} <- dispatch_async_job(event) do
              {:ok, persisted}
            else
              error -> {:error, error}
            end
          end

          defp verify_signature(_provider, _signature, _body), do: :ok
          defp parse_event(_provider, _body), do: {:ok, %{reference: "wh_123"}}

          defp persist_event(event) do
            WithdrawalWebhookEvent
            |> Ash.Changeset.for_create(:receive, %{provider_reference: event.reference})
            |> Ash.create(actor: %{is_system: true})
          end

          defp dispatch_async_job(event) do
            args = %{"provider_reference" => event.reference}
            Oban.insert(ProcessWithdrawalWebhook.new(args))
          end
        end

        defmodule IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook do
          def new(args), do: args
          def perform(_job), do: :ok
        end

        defmodule IgamingRef.Finance.WithdrawalWebhookEvent do
        end
        """
      )

      write_test_file(
        tmpdir,
        "automatic_runtime_webhook_scenario.exs",
        """
        defmodule IgamingRef.Finance.AutomaticRuntimeWebhookScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Finance.WithdrawalWebhook

          describe "Automatic runtime-backed webhook flow" do
            @scenario category: :compliance

            test "executes the webhook entrypoint" do
              assert {:ok, _} = WithdrawalWebhook.handle_webhook("stripe", "sig", "{}")
            end
          end
        end
        """
      )

      write_trace_file(
        tmpdir,
        "automatic_runtime_webhook_trace.json",
        %{
          "scenario_id" =>
            "IgamingRef.Finance.AutomaticRuntimeWebhookScenarioTest.automatic_runtime_backed_webhook_flow",
          "test_name" => "Automatic runtime-backed webhook flow executes the webhook entrypoint",
          "events" => [
            %{
              "type" => "entry",
              "kind" => "trigger_receive",
              "node_id" => "IgamingRef.Finance.WithdrawalWebhook",
              "focus_node_id" => "IgamingRef.Finance.WithdrawalWebhook",
              "module_function" => "IgamingRef.Finance.WithdrawalWebhook.handle_webhook",
              "capture_origin" => "automatic"
            }
          ]
        }
      )

      nodes = [
        node("IgamingRef.Finance.WithdrawalWebhook", "trigger"),
        %NodeEntry{
          id: "IgamingRef.Finance.WithdrawalWebhookEvent",
          module: "IgamingRef.Finance.WithdrawalWebhookEvent",
          type: "resource",
          domain: "Finance",
          description: "Webhook event",
          actions: [%{name: "receive", type: "create"}]
        },
        node("IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook", "job")
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert scenario.evidence_mode == :runtime
      assert scenario.trace_status == :present

      assert scenario.nodes == [
               "IgamingRef.Finance.WithdrawalWebhook",
               "IgamingRef.Finance.WithdrawalWebhookEvent",
               "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook"
             ]

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and
                 step.kind == :write and
                 step.node_id == "IgamingRef.Finance.WithdrawalWebhookEvent"
             end)

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and
                 step.kind == :job_enqueue and
                 step.node_id == "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook"
             end)
    end

    test "resolves local helper expansion against the current module instead of hardcoded domains" do
      tmpdir = tmp_project_root()

      write_lib_file(
        tmpdir,
        "operations/provider_callback.ex",
        """
        defmodule Demo.Operations.ProviderCallback do
          alias Demo.Operations.ProviderEvent
          alias Demo.Operations.Jobs.ProcessProviderCallback

          def handle_webhook(provider, signature, body) do
            with :ok <- verify_signature(provider, signature, body),
                 {:ok, event} <- parse_event(provider, body),
                 {:ok, persisted} <- persist_event(event),
                 {:ok, _job} <- dispatch_async_job(event) do
              {:ok, persisted}
            else
              error -> {:error, error}
            end
          end

          defp verify_signature(_provider, _signature, _body), do: :ok
          defp parse_event(_provider, _body), do: {:ok, %{reference: "cb_123"}}

          defp persist_event(event) do
            ProviderEvent
            |> Ash.Changeset.for_create(:receive, %{provider_reference: event.reference})
            |> Ash.create(actor: %{is_system: true})
          end

          defp dispatch_async_job(event) do
            args = %{"provider_reference" => event.reference}
            Oban.insert(ProcessProviderCallback.new(args))
          end
        end

        defmodule Demo.Operations.Jobs.ProcessProviderCallback do
          def new(args), do: args
          def perform(_job), do: :ok
        end

        defmodule Demo.Operations.ProviderEvent do
        end
        """
      )

      write_test_file(
        tmpdir,
        "provider_callback_scenario.exs",
        """
        defmodule Demo.Operations.ProviderCallbackScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias Demo.Operations.ProviderCallback

          describe "Provider callback flow" do
            @scenario category: :compliance

            test "expands local helper targets from the current module" do
              assert {:ok, _} = ProviderCallback.handle_webhook("demo", "sig", "{}")
            end
          end
        end
        """
      )

      write_trace_file(
        tmpdir,
        "provider_callback_trace.json",
        %{
          "scenario_id" => "Demo.Operations.ProviderCallbackScenarioTest.provider_callback_flow",
          "test_name" =>
            "Provider callback flow expands local helper targets from the current module",
          "events" => [
            %{
              "type" => "entry",
              "kind" => "trigger_receive",
              "node_id" => "Demo.Operations.ProviderCallback",
              "focus_node_id" => "Demo.Operations.ProviderCallback",
              "module_function" => "Demo.Operations.ProviderCallback.handle_webhook",
              "capture_origin" => "automatic"
            }
          ]
        }
      )

      nodes = [
        node("Demo.Operations.ProviderCallback", "trigger"),
        %NodeEntry{
          id: "Demo.Operations.ProviderEvent",
          module: "Demo.Operations.ProviderEvent",
          type: "resource",
          domain: "Operations",
          description: "Provider event",
          actions: [%{name: "receive", type: "create"}]
        },
        node("Demo.Operations.Jobs.ProcessProviderCallback", "job")
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert scenario.nodes == [
               "Demo.Operations.ProviderCallback",
               "Demo.Operations.ProviderEvent",
               "Demo.Operations.Jobs.ProcessProviderCallback"
             ]

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and
                 step.kind == :write and
                 step.node_id == "Demo.Operations.ProviderEvent"
             end)

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and
                 step.kind == :job_enqueue and
                 step.node_id == "Demo.Operations.Jobs.ProcessProviderCallback"
             end)
    end

    test "collapses duplicate adjacent runtime steps while preserving the canonical later event" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "duplicate_runtime_trace_test.exs",
        """
        defmodule IgamingRef.Finance.DuplicateRuntimeTraceTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          describe "Duplicate runtime trace flow" do
            @scenario category: :compliance

            test "keeps one canonical transfer entry" do
              :ok
            end
          end
        end
        """
      )

      write_trace_file(
        tmpdir,
        "duplicate_runtime_trace.json",
        %{
          "scenario_id" =>
            "IgamingRef.Finance.DuplicateRuntimeTraceTest.duplicate_runtime_trace_flow",
          "test_name" => "Duplicate runtime trace flow keeps one canonical transfer entry",
          "events" => [
            %{
              "sequence" => 1,
              "type" => "entry",
              "kind" => "action_execute",
              "label" => "Run the approved WithdrawalTransfer pipeline",
              "node_id" => "IgamingRef.Finance.WithdrawalTransfer",
              "focus_node_id" => "IgamingRef.Finance.WithdrawalTransfer:step:0",
              "focus_targets" => ["IgamingRef.Finance.WithdrawalRequest"],
              "action" => "run",
              "module_function" => "Reactor.run"
            },
            %{
              "sequence" => 2,
              "type" => "entry",
              "kind" => "action_execute",
              "label" => "Enter WithdrawalTransfer pipeline",
              "node_id" => "IgamingRef.Finance.WithdrawalTransfer",
              "focus_node_id" => "IgamingRef.Finance.WithdrawalTransfer:step:0",
              "module_function" => "Reactor.run"
            }
          ]
        }
      )

      [scenario] =
        ScenarioExtractor.extract(tmpdir, [
          node("IgamingRef.Finance.WithdrawalTransfer", "transfer"),
          node("IgamingRef.Finance.WithdrawalRequest", "resource")
        ])

      assert length(scenario.flow) == 2

      [action_step, transfer_step] = scenario.flow
      assert action_step.label == "Run the approved WithdrawalTransfer pipeline"
      assert action_step.focus_node_id == "IgamingRef.Finance.WithdrawalTransfer:action:run"

      assert action_step.focus_targets == [
               "IgamingRef.Finance.WithdrawalRequest",
               "IgamingRef.Finance.WithdrawalTransfer:step:0"
             ]

      assert transfer_step.label == "Enter WithdrawalTransfer pipeline"
      assert transfer_step.focus_node_id == "IgamingRef.Finance.WithdrawalTransfer:step:0"

      assert scenario.graph_path == [
               "IgamingRef.Finance.WithdrawalTransfer:action:run",
               "IgamingRef.Finance.WithdrawalRequest",
               "IgamingRef.Finance.WithdrawalTransfer:step:0"
             ]
    end

    test "marks shallow job implementations instead of inventing downstream work" do
      tmpdir = tmp_project_root()

      write_lib_file(
        tmpdir,
        "finance/jobs/process_withdrawal_webhook.ex",
        """
        defmodule IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook do
          def perform(_job), do: :ok
        end
        """
      )

      write_test_file(
        tmpdir,
        "job_scenario.exs",
        """
        defmodule IgamingRef.Finance.JobScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook

          describe "Oban worker applies withdrawal webhook status" do
            @scenario category: :invariant

            test "accepts a normalized webhook job payload" do
              assert :ok = ProcessWithdrawalWebhook.perform(%{provider_reference: "wh_123"})
            end
          end
        end
        """
      )

      [scenario] =
        ScenarioExtractor.extract(tmpdir, [
          node("IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook", "job")
        ])

      assert Enum.any?(scenario.flow, fn step ->
               step.provenance == :expanded and step.label == "Job implementation is stubbed"
             end)
    end

    test "infers property category when metadata is omitted" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "bonus_event_property_test.exs",
        """
        defmodule IgamingRef.Promotions.BonusEventPropertyScenarioTest do
          use ExUnit.Case, async: true

          alias IgamingRef.Promotions.BonusEvent

          describe "Bonus event property" do
            property "creates the event via ingest action" do
              Ash.create(BonusEvent, %{kind: :deposit_completed}, action: :ingest, actor: :system)
            end
          end
        end
        """
      )

      nodes = [
        %NodeEntry{
          id: "IgamingRef.Promotions.BonusEvent",
          module: "IgamingRef.Promotions.BonusEvent",
          type: "resource",
          domain: "Promotions",
          description: "Bonus event",
          actions: [%{name: "ingest", type: "create"}]
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)
      assert scenario.category == :property
    end

    test "scenario entries remain Jason encodable when flow uses Step structs" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "json_scenario_test.exs",
        """
        defmodule IgamingRef.Promotions.JsonScenarioTest do
          use ExUnit.Case, async: true

          alias IgamingRef.Promotions.BonusEvent

          describe "JSON scenario" do
            test "invokes the ingest action with canonical trigger attributes" do
              Ash.create(
                BonusEvent,
                %{kind: :deposit_completed},
                action: :ingest,
                actor: %{is_system: true}
              )
            end
          end
        end
        """
      )

      nodes = [
        %NodeEntry{
          id: "IgamingRef.Promotions.BonusEvent",
          module: "IgamingRef.Promotions.BonusEvent",
          type: "resource",
          domain: "Promotions",
          description: "Bonus event",
          actions: [%{name: "ingest", type: "create"}]
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)
      encoded = Jason.encode!(scenario)

      assert encoded =~ "\"flow\""
      assert encoded =~ "\"kind\":\"action_execute\""
      assert encoded =~ "\"node_id\":\"IgamingRef.Promotions.BonusEvent\""
    end

    test "page scenarios collapse duplicated disconnected and connected mount cycles" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "home_live_test.exs",
        """
        defmodule IgamingRef.Web.HomeLiveTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          describe "home page" do
            test "renders featured games and active promotions from live data" do
              :ok
            end

            test "shows stable empty states when no data is available" do
              :ok
            end
          end
        end
        """
      )

      write_trace_file(
        tmpdir,
        "home_page_a.json",
        %{
          "scenario_id" => "IgamingRef.Web.HomeLiveTest.home_page",
          "test_name" => "renders featured games and active promotions from live data",
          "events" => [
            %{"sequence" => 1, "node_id" => "IgamingRef.Web.HomeLive", "focus_node_id" => "IgamingRef.Web.HomeLive", "action_kind" => "entry"},
            %{"sequence" => 2, "node_id" => "IgamingRef.Gaming.Game", "focus_node_id" => "IgamingRef.Gaming.Game", "action_kind" => "read"},
            %{"sequence" => 3, "node_id" => "IgamingRef.Promotions.BonusCampaign", "focus_node_id" => "IgamingRef.Promotions.BonusCampaign", "action_kind" => "read"},
            %{"sequence" => 4, "node_id" => "IgamingRef.Web.HomeLive", "focus_node_id" => "IgamingRef.Web.HomeLive", "action_kind" => "entry"},
            %{"sequence" => 5, "node_id" => "IgamingRef.Gaming.Game", "focus_node_id" => "IgamingRef.Gaming.Game", "action_kind" => "read"},
            %{"sequence" => 6, "node_id" => "IgamingRef.Promotions.BonusCampaign", "focus_node_id" => "IgamingRef.Promotions.BonusCampaign", "action_kind" => "read"}
          ]
        }
      )

      write_trace_file(
        tmpdir,
        "home_page_b.json",
        %{
          "scenario_id" => "IgamingRef.Web.HomeLiveTest.home_page",
          "test_name" => "shows stable empty states when no data is available",
          "events" => [
            %{"sequence" => 1, "node_id" => "IgamingRef.Web.HomeLive", "focus_node_id" => "IgamingRef.Web.HomeLive", "action_kind" => "entry"},
            %{"sequence" => 2, "node_id" => "IgamingRef.Gaming.Game", "focus_node_id" => "IgamingRef.Gaming.Game", "action_kind" => "read"},
            %{"sequence" => 3, "node_id" => "IgamingRef.Promotions.BonusCampaign", "focus_node_id" => "IgamingRef.Promotions.BonusCampaign", "action_kind" => "read"},
            %{"sequence" => 4, "node_id" => "IgamingRef.Web.HomeLive", "focus_node_id" => "IgamingRef.Web.HomeLive", "action_kind" => "entry"},
            %{"sequence" => 5, "node_id" => "IgamingRef.Gaming.Game", "focus_node_id" => "IgamingRef.Gaming.Game", "action_kind" => "read"},
            %{"sequence" => 6, "node_id" => "IgamingRef.Promotions.BonusCampaign", "focus_node_id" => "IgamingRef.Promotions.BonusCampaign", "action_kind" => "read"}
          ]
        }
      )

      nodes = [
        node("IgamingRef.Web.HomeLive", "page"),
        %NodeEntry{
          id: "IgamingRef.Gaming.Game",
          module: "IgamingRef.Gaming.Game",
          type: "resource",
          domain: "Gaming",
          description: "Game",
          actions: [%{name: "read", type: "read"}]
        },
        %NodeEntry{
          id: "IgamingRef.Promotions.BonusCampaign",
          module: "IgamingRef.Promotions.BonusCampaign",
          type: "resource",
          domain: "Promotions",
          description: "Bonus campaign",
          actions: [%{name: "read", type: "read"}]
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert Enum.map(scenario.flow, & &1.test_name) == [
               "renders featured games and active promotions from live data",
               "renders featured games and active promotions from live data",
               "renders featured games and active promotions from live data"
             ]

      assert scenario.graph_path == [
               "IgamingRef.Web.HomeLive",
               "IgamingRef.Gaming.Game:action:read",
               "IgamingRef.Promotions.BonusCampaign:action:read"
             ]
    end

    test "page scenarios drop shorter prefix-only variants across tests" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "auth_live_test.exs",
        """
        defmodule IgamingRef.Web.AuthLiveTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          describe "auth page" do
            test "renders the login form with its active fields" do
              :ok
            end

            test "shows an error flash for invalid credentials" do
              :ok
            end

            test "redirects after a successful password sign in" do
              :ok
            end
          end
        end
        """
      )

      write_trace_file(
        tmpdir,
        "auth_page_a.json",
        %{
          "scenario_id" => "IgamingRef.Web.AuthLiveTest.auth_page",
          "test_name" => "renders the login form with its active fields",
          "events" => [
            %{"sequence" => 1, "node_id" => "IgamingRef.Web.AuthLive", "focus_node_id" => "IgamingRef.Web.AuthLive", "action_kind" => "entry"},
            %{"sequence" => 2, "node_id" => "IgamingRef.Web.AuthLive", "focus_node_id" => "IgamingRef.Web.AuthLive", "action_kind" => "entry"}
          ]
        }
      )

      for name <- [
            "shows an error flash for invalid credentials",
            "redirects after a successful password sign in"
          ] do
        write_trace_file(
          tmpdir,
          "auth_#{String.replace(name, ~r/[^a-z]+/, "_")}.json",
          %{
            "scenario_id" => "IgamingRef.Web.AuthLiveTest.auth_page",
            "test_name" => name,
            "events" => [
              %{"sequence" => 1, "node_id" => "IgamingRef.Web.AuthLive", "focus_node_id" => "IgamingRef.Web.AuthLive", "action_kind" => "entry"},
              %{"sequence" => 2, "node_id" => "IgamingRef.Web.AuthLive", "focus_node_id" => "IgamingRef.Web.AuthLive", "action_kind" => "entry"},
              %{"sequence" => 3, "node_id" => "IgamingRef.Accounts.User", "focus_node_id" => "IgamingRef.Accounts.User", "action_kind" => "read"}
            ]
          }
        )
      end

      nodes = [
        node("IgamingRef.Web.AuthLive", "page"),
        %NodeEntry{
          id: "IgamingRef.Accounts.User",
          module: "IgamingRef.Accounts.User",
          type: "resource",
          domain: "Accounts",
          description: "User",
          actions: [%{name: "sign_in_with_password", type: "read"}]
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert length(scenario.flow) == 2
      assert Enum.map(scenario.flow, & &1.node_id) == [
               "IgamingRef.Web.AuthLive",
               "IgamingRef.Accounts.User"
             ]

      assert scenario.graph_path == [
               "IgamingRef.Web.AuthLive",
               "IgamingRef.Accounts.User:action:sign_in_with_password"
             ]
    end

    test "page scenarios keep the richest unique interaction path instead of concatenating repeated prefixes" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "game_live_test.exs",
        """
        defmodule IgamingRef.Web.GameLiveTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          describe "game page" do
            test "loads the routed game and the current player's wallet" do
              :ok
            end

            test "clicking play creates a game session for the routed game" do
              :ok
            end
          end
        end
        """
      )

      write_trace_file(
        tmpdir,
        "game_page_a.json",
        %{
          "scenario_id" => "IgamingRef.Web.GameLiveTest.game_page",
          "test_name" => "loads the routed game and the current player's wallet",
          "events" => [
            %{"sequence" => 1, "node_id" => "IgamingRef.Web.GameLive", "focus_node_id" => "IgamingRef.Web.GameLive", "action_kind" => "entry"},
            %{"sequence" => 2, "node_id" => "IgamingRef.Gaming.Game", "focus_node_id" => "IgamingRef.Gaming.Game", "action_kind" => "read"},
            %{"sequence" => 3, "node_id" => "IgamingRef.Finance.Wallet", "focus_node_id" => "IgamingRef.Finance.Wallet", "action_kind" => "read"},
            %{"sequence" => 4, "node_id" => "IgamingRef.Web.GameLive", "focus_node_id" => "IgamingRef.Web.GameLive", "action_kind" => "entry"},
            %{"sequence" => 5, "node_id" => "IgamingRef.Gaming.Game", "focus_node_id" => "IgamingRef.Gaming.Game", "action_kind" => "read"},
            %{"sequence" => 6, "node_id" => "IgamingRef.Finance.Wallet", "focus_node_id" => "IgamingRef.Finance.Wallet", "action_kind" => "read"}
          ]
        }
      )

      write_trace_file(
        tmpdir,
        "game_page_b.json",
        %{
          "scenario_id" => "IgamingRef.Web.GameLiveTest.game_page",
          "test_name" => "clicking play creates a game session for the routed game",
          "events" => [
            %{"sequence" => 1, "node_id" => "IgamingRef.Web.GameLive", "focus_node_id" => "IgamingRef.Web.GameLive", "action_kind" => "entry"},
            %{"sequence" => 2, "node_id" => "IgamingRef.Gaming.Game", "focus_node_id" => "IgamingRef.Gaming.Game", "action_kind" => "read"},
            %{"sequence" => 3, "node_id" => "IgamingRef.Finance.Wallet", "focus_node_id" => "IgamingRef.Finance.Wallet", "action_kind" => "read"},
            %{"sequence" => 4, "node_id" => "IgamingRef.Web.GameLive", "focus_node_id" => "IgamingRef.Web.GameLive", "action_kind" => "entry"},
            %{"sequence" => 5, "node_id" => "IgamingRef.Gaming.Game", "focus_node_id" => "IgamingRef.Gaming.Game", "action_kind" => "read"},
            %{"sequence" => 6, "node_id" => "IgamingRef.Finance.Wallet", "focus_node_id" => "IgamingRef.Finance.Wallet", "action_kind" => "read"},
            %{"sequence" => 7, "node_id" => "IgamingRef.Gaming.GameSession", "focus_node_id" => "IgamingRef.Gaming.GameSession", "action_kind" => "read"},
            %{"sequence" => 8, "node_id" => "IgamingRef.Gaming.GameSession", "focus_node_id" => "IgamingRef.Gaming.GameSession", "action_kind" => "read"}
          ]
        }
      )

      nodes = [
        node("IgamingRef.Web.GameLive", "page"),
        %NodeEntry{
          id: "IgamingRef.Gaming.Game",
          module: "IgamingRef.Gaming.Game",
          type: "resource",
          domain: "Gaming",
          description: "Game",
          actions: [%{name: "read", type: "read"}]
        },
        %NodeEntry{
          id: "IgamingRef.Finance.Wallet",
          module: "IgamingRef.Finance.Wallet",
          type: "resource",
          domain: "Finance",
          description: "Wallet",
          actions: [%{name: "read", type: "read"}]
        },
        %NodeEntry{
          id: "IgamingRef.Gaming.GameSession",
          module: "IgamingRef.Gaming.GameSession",
          type: "resource",
          domain: "Gaming",
          description: "Game session",
          actions: [%{name: "read", type: "read"}]
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert Enum.map(scenario.flow, & &1.node_id) == [
               "IgamingRef.Web.GameLive",
               "IgamingRef.Gaming.Game",
               "IgamingRef.Finance.Wallet",
               "IgamingRef.Gaming.GameSession"
             ]

      assert scenario.graph_path == [
               "IgamingRef.Web.GameLive",
               "IgamingRef.Gaming.Game:action:read",
               "IgamingRef.Finance.Wallet:action:read",
               "IgamingRef.Gaming.GameSession:action:read"
             ]
    end
  end

  defp node(module_name, type) do
    %NodeEntry{
      id: module_name,
      module: module_name,
      type: type,
      domain: module_name |> String.split(".") |> Enum.at(1) || "Test",
      description: module_name
    }
  end

  defp tmp_project_root do
    path =
      Path.join(
        System.tmp_dir!(),
        "foundry_test_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf(path)
    File.mkdir_p!(Path.join(path, "test"))
    File.mkdir_p!(Path.join(path, "lib"))
    path
  end

  defp write_test_file(project_root, filename, content) do
    path = Path.join([project_root, "test", filename])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  defp write_lib_file(project_root, filename, content) do
    path = Path.join([project_root, "lib", filename])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  defp write_trace_file(project_root, filename, payload) do
    path = Path.join([project_root, ".foundry", "scenario_traces", filename])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(payload))
    path
  end
end
