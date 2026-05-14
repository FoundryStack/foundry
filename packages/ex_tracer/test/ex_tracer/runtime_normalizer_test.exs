defmodule ExTracer.RuntimeNormalizerTest do
  use ExUnit.Case, async: true

  alias ExTracer.{Lookup, RuntimeNormalizer, RuntimeTrace}

  test "normalizes runtime atoms and infers exact action focus from generic action metadata" do
    trace =
      RuntimeTrace.from_map(%{
        "events" => [
          %{
            "sequence" => 1,
            "type" => "observation",
            "node_id" => "Demo.User",
            "action_kind" => "read",
            "capture_origin" => "ash_tracer"
          },
          %{
            "sequence" => 2,
            "type" => "entry",
            "node_id" => "Demo.WithdrawalRequest",
            "kind" => "create",
            "capture_origin" => "automatic"
          }
        ]
      })

    steps =
      RuntimeNormalizer.normalize(
        trace,
        %{name: "auth", kind: :test, line: 10},
        lookup(),
        []
      )

    assert [
             %{type: :observation, kind: :read, action: "sign_in_with_password"},
             %{type: :entry, kind: :create, action: "create"}
           ] = steps

    assert Enum.map(steps, & &1.focus_node_id) == [
             "Demo.User:action:sign_in_with_password",
             "Demo.WithdrawalRequest:action:create"
           ]

    assert Enum.map(steps, & &1.capture_origin) == ["ash_tracer", "automatic"]
  end

  test "preserves exact focus node ids supplied by runtime events" do
    trace =
      RuntimeTrace.from_map(%{
        "events" => [
          %{
            "sequence" => 1,
            "type" => "entry",
            "node_id" => "Demo.WithdrawalRequest",
            "focus_node_id" => "Demo.WithdrawalRequest:action:approve",
            "action" => "approve"
          }
        ]
      })

    [step] =
      RuntimeNormalizer.normalize(
        trace,
        %{name: "approve", kind: :test, line: 10},
        lookup(),
        []
      )

    assert step.focus_node_id == "Demo.WithdrawalRequest:action:approve"
    assert step.action == "approve"
  end

  defp lookup do
    %Lookup{
      by_id: %{
        "Demo.User" => %{
          id: "Demo.User",
          type: "resource",
          actions: [%{name: "sign_in_with_password", type: "read"}]
        },
        "Demo.WithdrawalRequest" => %{
          id: "Demo.WithdrawalRequest",
          type: "resource",
          actions: [
            %{name: "create", type: "create"},
            %{name: "approve", type: "update"}
          ]
        }
      }
    }
  end
end
