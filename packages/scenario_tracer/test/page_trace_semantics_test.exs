defmodule ScenarioTracer.PageTraceSemanticsTest do
  use ExUnit.Case, async: true

  alias ExTracer.{Lookup, Step}
  alias ScenarioTracer.PageTraceSemantics

  test "classifies framework mount, app behavior, and helper observation without ex_tracer leakage" do
    wrapped =
      [
        step(%{
          node_id: "Demo.Web.AuthLive",
          focus_node_id: "Demo.Web.AuthLive",
          kind: :entry,
          capture_origin: "live_view_mount"
        }),
        step(%{
          node_id: "Demo.User",
          focus_node_id: "Demo.User",
          kind: :read,
          type: :observation,
          capture_origin: "ash_tracer"
        }),
        step(%{
          node_id: "Demo.User",
          focus_node_id: "Demo.User",
          kind: :read,
          type: :observation,
          capture_origin: "automatic"
        })
      ]
      |> PageTraceSemantics.wrap_flow(lookup())

    assert Enum.map(wrapped, & &1.role) == [
             :framework_mount,
             :app_behavior,
             :test_observation
           ]
  end

  test "treats plain static page entries as framework mounts and resource reads as app behavior" do
    wrapped =
      [
        step(%{node_id: "Demo.Web.HomeLive", focus_node_id: "Demo.Web.HomeLive", kind: :entry}),
        step(%{
          node_id: "Demo.Game",
          focus_node_id: "Demo.Game",
          kind: :read,
          type: :observation
        })
      ]
      |> PageTraceSemantics.wrap_flow(lookup())

    assert Enum.map(wrapped, & &1.role) == [:framework_mount, :app_behavior]
  end

  defp lookup do
    %Lookup{
      by_id: %{
        "Demo.Web.AuthLive" => %{id: "Demo.Web.AuthLive", type: "page"},
        "Demo.Web.HomeLive" => %{id: "Demo.Web.HomeLive", type: "page"},
        "Demo.Game" => %{id: "Demo.Game", type: "resource"},
        "Demo.User" => %{id: "Demo.User", type: "resource"}
      }
    }
  end

  defp step(attrs) do
    Step.new(
      Map.merge(
        %{
          type: :entry,
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
