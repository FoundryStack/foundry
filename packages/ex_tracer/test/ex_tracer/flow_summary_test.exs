defmodule ExTracer.FlowSummaryTest do
  use ExUnit.Case, async: true

  alias ExTracer.{FlowSummary, Step}

  test "collapses duplicate adjacent runtime steps but keeps distinct provenance" do
    executed =
      Step.new(%{
        provenance: :executed,
        type: :entry,
        kind: :action_execute,
        node_id: "Demo.Payments.Withdrawal",
        focus_node_id: "Demo.Payments.Withdrawal",
        status: :passed,
        test_name: "flow"
      })

    expanded =
      Step.new(%{
        provenance: :expanded,
        type: :entry,
        kind: :action_execute,
        node_id: "Demo.Payments.Withdrawal",
        focus_node_id: "Demo.Payments.Withdrawal",
        status: :passed,
        test_name: "flow"
      })

    duplicate_later =
      Step.new(%{
        provenance: :executed,
        type: :entry,
        kind: :action_execute,
        node_id: "Demo.Payments.Withdrawal",
        focus_node_id: "Demo.Payments.Withdrawal",
        status: :failed,
        test_name: "flow",
        details: "later"
      })

    collapsed =
      FlowSummary.collapse_duplicate_runtime_steps([executed, duplicate_later, expanded])

    assert length(collapsed) == 2
    assert Enum.at(collapsed, 0).status == :failed
    assert Enum.at(collapsed, 0).details == "later"
    assert Enum.at(collapsed, 1).provenance == :expanded
  end

  test "derives nodes and graph path from expanded focus targets" do
    flow = [
      Step.new(%{
        node_id: "Demo.Finance.WithdrawalWebhook",
        focus_node_id: "Demo.Finance.WithdrawalWebhook",
        focus_targets: ["Demo.Finance.WithdrawalWebhookEvent:action:receive"]
      }),
      Step.new(%{
        node_id: "Demo.Finance.WithdrawalWebhookEvent",
        focus_node_id: "Demo.Finance.WithdrawalWebhookEvent:action:receive",
        focus_targets: ["Demo.Finance.Jobs.ProcessWithdrawalWebhook"]
      })
    ]

    {nodes, graph_path} = FlowSummary.derive_flow_summaries(flow)

    assert nodes == [
             "Demo.Finance.WithdrawalWebhook",
             "Demo.Finance.WithdrawalWebhookEvent",
             "Demo.Finance.Jobs.ProcessWithdrawalWebhook"
           ]

    assert graph_path == [
             "Demo.Finance.WithdrawalWebhook",
             "Demo.Finance.WithdrawalWebhookEvent:action:receive",
             "Demo.Finance.Jobs.ProcessWithdrawalWebhook"
           ]
  end
end
