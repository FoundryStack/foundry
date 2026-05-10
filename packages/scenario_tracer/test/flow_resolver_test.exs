defmodule ScenarioTracer.FlowResolverTest do
  use ExUnit.Case, async: true

  alias ExTracer.Step
  alias ScenarioTracer.FlowResolver

  test "keeps separate static and runtime evidence while resolving in runtime order" do
    static_flow = [
      step(%{node_id: "Demo.A", focus_node_id: "Demo.A", kind: :entry, label: "static a"}),
      step(%{node_id: "Demo.B", focus_node_id: "Demo.B", kind: :read, label: "static b"})
    ]

    runtime_flow = [
      step(%{
        node_id: "Demo.B",
        focus_node_id: "Demo.B",
        kind: :read,
        provenance: :executed,
        label: "runtime b"
      }),
      step(%{
        node_id: "Demo.A",
        focus_node_id: "Demo.A",
        kind: :entry,
        provenance: :executed,
        label: "runtime a"
      })
    ]

    resolved = FlowResolver.resolve(static_flow, runtime_flow, %{}, [])

    assert Enum.map(resolved.resolved_flow, & &1.node_id) == ["Demo.B", "Demo.A"]
    assert Enum.map(resolved.resolved_flow, & &1.label) == ["runtime b", "runtime a"]
    assert resolved.diagnostics.mode == :runtime_enriched
  end

  test "keeps expanded static steps as inferred structure after a matched runtime anchor" do
    static_flow = [
      step(%{node_id: "Demo.Trigger", focus_node_id: "Demo.Trigger", kind: :entry}),
      step(%{
        node_id: "Demo.Event",
        focus_node_id: "Demo.Event:action:create",
        kind: :write,
        provenance: :expanded
      }),
      step(%{
        node_id: "Demo.Job",
        focus_node_id: "Demo.Job",
        kind: :job_enqueue,
        provenance: :expanded
      })
    ]

    runtime_flow = [
      step(%{
        node_id: "Demo.Trigger",
        focus_node_id: "Demo.Trigger",
        kind: :entry,
        provenance: :executed
      })
    ]

    resolved = FlowResolver.resolve(static_flow, runtime_flow, %{}, [])

    assert Enum.map(resolved.resolved_flow, & &1.node_id) == [
             "Demo.Trigger",
             "Demo.Event",
             "Demo.Job"
           ]

    assert Enum.map(resolved.resolved_flow, & &1.provenance) == [:executed, :expanded, :expanded]
  end

  test "keeps meaningful unmatched static bridge steps between matched runtime anchors" do
    static_flow = [
      step(%{
        node_id: "Demo.Request",
        focus_node_id: "Demo.Request:action:create",
        action: "create"
      }),
      step(%{
        node_id: "Demo.Request",
        focus_node_id: "Demo.Request:action:approve",
        kind: :action_prepare,
        action: "approve"
      }),
      step(%{node_id: "Demo.Transfer", focus_node_id: "Demo.Transfer", action: "run"})
    ]

    runtime_flow = [
      step(%{
        node_id: "Demo.Request",
        focus_node_id: "Demo.Request:action:create",
        action: "create"
      }),
      step(%{node_id: "Demo.Transfer", focus_node_id: "Demo.Transfer", action: "run"})
    ]

    resolved = FlowResolver.resolve(static_flow, runtime_flow, %{}, [])

    assert Enum.map(resolved.resolved_flow, & &1.focus_node_id) == [
             "Demo.Request:action:create",
             "Demo.Request:action:approve",
             "Demo.Transfer"
           ]
  end

  test "falls back to static flow when runtime evidence is missing" do
    static_flow = [step(%{node_id: "Demo.Rule", focus_node_id: "Demo.Rule", kind: :rule_check})]

    resolved = FlowResolver.resolve(static_flow, [], %{}, [])

    assert resolved.resolved_flow == static_flow
    assert resolved.diagnostics.mode == :static_fallback
  end

  defp step(attrs) do
    Step.new(
      Map.merge(
        %{
          type: :reaction,
          provenance: :executed,
          status: :passed,
          focus_targets: [],
          emits: [],
          line: 1,
          test_kind: :test
        },
        attrs
      )
    )
  end
end
