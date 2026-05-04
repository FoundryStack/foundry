defmodule Foundry.Context.ScenarioExtractorTest do
  use ExUnit.Case, async: true

  alias Foundry.Context.NodeEntry
  alias Foundry.Context.ScenarioExtractor

  describe "extract/2" do
    test "returns empty list when test directory does not exist" do
      assert ScenarioExtractor.extract("/nonexistent/path", []) == []
    end

    test "extracts explicit @scenario flow metadata and resolves shorthand node ids" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "withdrawal_webhook_scenario.exs",
        """
        defmodule IgamingRef.Finance.WithdrawalWebhookScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          describe "Webhook processing flow" do
            @scenario category: :compliance,
                      compliance_links: ["RG-UK-014"],
                      flow: [
                        %{id: "receive", type: :entry, node: "Finance.WithdrawalWebhook", label: "Validate signature", action: "handle_webhook", focus_targets: ["Finance.WithdrawalWebhookEvent"]},
                        %{id: "persist", type: :reaction, node: "Finance.WithdrawalWebhookEvent", label: "Persist event", focus_targets: ["Finance.Jobs.ProcessWithdrawalWebhook"]},
                        %{id: "process", type: :job, node: "Finance.Jobs.ProcessWithdrawalWebhook", label: "Apply status"}
                      ]

            test "processes the webhook" do
              :ok
            end
          end
        end
        """
      )

      nodes = [
        node("IgamingRef.Finance.WithdrawalWebhook", "resource"),
        node("IgamingRef.Finance.WithdrawalWebhookEvent", "resource"),
        node("IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook", "job")
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert scenario.category == :compliance
      assert scenario.compliance_links == ["RG-UK-014"]

      assert scenario.nodes == [
               "IgamingRef.Finance.WithdrawalWebhook",
               "IgamingRef.Finance.WithdrawalWebhookEvent",
               "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook"
             ]

      assert [
               %{id: "receive", node_id: "IgamingRef.Finance.WithdrawalWebhook"},
               %{id: "persist", node_id: "IgamingRef.Finance.WithdrawalWebhookEvent"},
               %{id: "process", node_id: "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook"}
             ] = Enum.map(scenario.flow, &Map.take(&1, [:id, :node_id]))

      assert Enum.at(scenario.flow, 0).focus_node_id == "IgamingRef.Finance.WithdrawalWebhook"

      assert Enum.at(scenario.flow, 0).focus_targets == [
               "IgamingRef.Finance.WithdrawalWebhookEvent"
             ]
    end

    test "resolves exact reactor and transfer focus hints into generated graph child ids" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "bonus_focus_scenario.exs",
        """
        defmodule IgamingRef.Promotions.BonusFocusScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          describe "Bonus focus flow" do
            @scenario category: :property,
                      flow: [
                        %{id: "evaluate", node: "Promotions.BonusEvaluationReactor", step_name: "find_matching_campaigns", focus_targets: ["Promotions.BonusGrantTransfer"], next_step_names: ["create_bonus_grant"]},
                        %{id: "grant", node: "Promotions.BonusGrantTransfer", step_name: "create_bonus_grant", focus_targets: ["Promotions.BonusGrant"]}
                      ]

            test "focuses exact graph steps" do
              :ok
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
            %{name: "load_event"},
            %{name: "load_player"},
            %{name: "find_matching_campaigns"}
          ]
        },
        %NodeEntry{
          id: "IgamingRef.Promotions.BonusGrantTransfer",
          module: "IgamingRef.Promotions.BonusGrantTransfer",
          type: "transfer",
          domain: "Promotions",
          description: "Bonus grant transfer",
          steps: [%{name: "load_context"}, %{name: "create_bonus_grant"}]
        },
        node("IgamingRef.Promotions.BonusGrant", "resource")
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert Enum.at(scenario.flow, 0).focus_node_id ==
               "IgamingRef.Promotions.BonusEvaluationReactor:step:2"

      assert Enum.at(scenario.flow, 0).focus_targets == [
               "IgamingRef.Promotions.BonusGrantTransfer:step:1"
             ]

      assert Enum.at(scenario.flow, 1).focus_node_id ==
               "IgamingRef.Promotions.BonusGrantTransfer:step:1"
    end

    test "infers rule-focused flow steps from executable test code" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "transfers_test.exs",
        """
        defmodule IgamingRef.Finance.WithdrawalTransferTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Finance.Rules.SufficientBalance

          describe "SufficientBalance" do
            @scenario category: :invariant

            test "rejects when amount exceeds balance" do
              assert {:error, :insufficient_balance, _} =
                       SufficientBalance.evaluate(%{wallet: wallet, amount: amount}, nil)
            end
          end
        end
        """
      )

      nodes = [
        %NodeEntry{
          id: "IgamingRef.Finance.Rules.SufficientBalance",
          module: "IgamingRef.Finance.Rules.SufficientBalance",
          type: "rule",
          domain: "Finance",
          description: "Sufficient balance rule"
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert scenario.category == :invariant
      assert scenario.nodes == ["IgamingRef.Finance.Rules.SufficientBalance"]

      assert [%{type: :assertion, action: "evaluate"}] =
               Enum.map(scenario.flow, &Map.take(&1, [:type, :action]))

      assert hd(scenario.flow).focus_node_id == "IgamingRef.Finance.Rules.SufficientBalance"
    end

    test "infers resource action focus from executable Ash calls" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "bonus_event_test.exs",
        """
        defmodule IgamingRef.Promotions.BonusEventScenarioTest do
          use ExUnit.Case, async: true
          use Foundry.TestScenario

          alias IgamingRef.Promotions.BonusEvent

          describe "Bonus event is persisted" do
            @scenario category: :property

            test "creates the event" do
              Ash.create(BonusEvent, :receive, %{kind: :deposit}, actor: :system)
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
          actions: [%{name: "receive", type: "create"}]
        }
      ]

      [scenario] = ScenarioExtractor.extract(tmpdir, nodes)

      assert hd(scenario.flow).focus_node_id == "IgamingRef.Promotions.BonusEvent:action:receive"
      assert scenario.graph_path == ["IgamingRef.Promotions.BonusEvent:action:receive"]
    end

    test "ignores describe blocks without @scenario metadata" do
      tmpdir = tmp_project_root()

      write_test_file(
        tmpdir,
        "regular_test.exs",
        """
        defmodule RegularTest do
          use ExUnit.Case, async: true

          describe "Regular test without scenario metadata" do
            test "works" do
              assert 1 + 1 == 2
            end
          end
        end
        """
      )

      assert ScenarioExtractor.extract(tmpdir, []) == []
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
    path = Path.join(System.tmp_dir!(), "foundry_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(path, "test"))
    path
  end

  defp write_test_file(project_root, filename, content) do
    path = Path.join([project_root, "test", filename])
    File.write!(path, content)
    path
  end
end
