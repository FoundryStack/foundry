defmodule ExTracer.FlowSummaryTest do
  use ExUnit.Case, async: true

  alias ExTracer.{FlowSummary, Step}

  test "collapses only exact duplicate adjacent runtime steps but keeps distinct instrumentation steps" do
    executed =
      Step.new(%{
        provenance: :executed,
        type: :entry,
        kind: :action_execute,
        node_id: "Demo.Payments.Withdrawal",
        focus_node_id: "Demo.Payments.Withdrawal",
        status: :passed,
        test_name: "flow",
        module_function: "Ash.create",
        capture_origin: "ash_tracer"
      })

    duplicate_same_instrumentation =
      Step.new(%{
        provenance: :executed,
        type: :entry,
        kind: :action_execute,
        node_id: "Demo.Payments.Withdrawal",
        focus_node_id: "Demo.Payments.Withdrawal",
        status: :failed,
        test_name: "flow",
        details: "later",
        module_function: "Ash.create",
        capture_origin: "ash_tracer"
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
        status: :passed,
        test_name: "flow",
        details: "other instrumentation",
        module_function: "Ash.create",
        source_snippet: "Withdrawal.create()",
        line: 42,
        capture_origin: "automatic"
      })

    collapsed =
      FlowSummary.collapse_duplicate_runtime_steps([
        executed,
        duplicate_same_instrumentation,
        duplicate_later,
        expanded
      ])

    assert length(collapsed) == 3
    assert Enum.at(collapsed, 0).status == :failed
    assert Enum.at(collapsed, 0).details == "later"
    assert Enum.at(collapsed, 1).details == "other instrumentation"
    assert Enum.at(collapsed, 2).provenance == :expanded
  end

  test "derives nodes and graph path from expanded focus targets without collapsing repeated action focus" do
    flow = [
      Step.new(%{
        node_id: "Demo.Finance.WithdrawalWebhook",
        focus_node_id: "Demo.Finance.WithdrawalWebhook",
        focus_targets: ["Demo.Finance.WithdrawalWebhookEvent:action:receive"]
      }),
      Step.new(%{
        node_id: "Demo.Finance.WithdrawalWebhookEvent",
        focus_node_id: "Demo.Finance.WithdrawalWebhookEvent:action:receive",
        focus_targets: ["Demo.Finance.WithdrawalWebhookEvent:action:persist"],
        action: "receive"
      }),
      Step.new(%{
        node_id: "Demo.Finance.WithdrawalWebhookEvent",
        focus_node_id: "Demo.Finance.WithdrawalWebhookEvent:action:persist",
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
             "Demo.Finance.WithdrawalWebhookEvent:action:persist",
             "Demo.Finance.Jobs.ProcessWithdrawalWebhook"
           ]
  end
end
