defmodule Foundry.Context.Scenarios.CallClassifierTest do
  use ExUnit.Case, async: true

  alias ExTracer.Lookup
  alias Foundry.Context.NodeEntry
  alias Foundry.Context.Scenarios.CallClassifier

  test "classifies piped Ash.Changeset calls as action preparation steps" do
    lookup =
      %Lookup{
        by_id: %{
          "Demo.Finance.WithdrawalRequest" => %NodeEntry{
            id: "Demo.Finance.WithdrawalRequest",
            module: "Demo.Finance.WithdrawalRequest",
            type: "resource",
            domain: "Finance",
            description: "Withdrawal request",
            actions: [%{name: "approve", type: "update"}]
          }
        },
        aliases: %{
          "Demo.Finance.WithdrawalRequest" => "Demo.Finance.WithdrawalRequest",
          "WithdrawalRequest" => "Demo.Finance.WithdrawalRequest"
        }
      }

    step =
      CallClassifier.classify_ast_call(
        {:__aliases__, [], [:Ash, :Changeset]},
        :for_update,
        [{:__aliases__, [], [:WithdrawalRequest]}, :approve, {:%{}, [], []}],
        %{"WithdrawalRequest" => "Demo.Finance.WithdrawalRequest"},
        lookup,
        %{
          alias_map: %{"WithdrawalRequest" => "Demo.Finance.WithdrawalRequest"},
          line: 12,
          test_name: "prepares",
          test_kind: :test,
          assertion_context: nil
        }
      )

    assert step.kind == :action_prepare
    assert step.node_id == "Demo.Finance.WithdrawalRequest"
    assert step.focus_node_id == "Demo.Finance.WithdrawalRequest:action:approve"
    assert step.action == "approve"
  end

  test "builds automatic runtime trace attrs for webhook entrypoints" do
    ast = quote(do: WithdrawalWebhook.handle_webhook("stripe", "sig", "{}"))

    {{:., _, [module_ast, fun]}, _, args} = ast

    attrs = CallClassifier.runtime_trace_attrs(module_ast, fun, args, ast, __ENV__)

    assert attrs.node_id == "WithdrawalWebhook"
    assert attrs.kind == :trigger_receive
    assert attrs.capture_origin == :automatic
    assert attrs.module_function == "WithdrawalWebhook.handle_webhook"
  end
end
