defmodule ScenarioTracer.PageTraceNormalizerTest do
  use ExUnit.Case, async: true

  alias ExTracer.{Lookup, Step}
  alias ScenarioTracer.PageTraceNormalizer

  test "collapses duplicated disconnected and connected mount cycles into one canonical path" do
    normalized =
      normalize([
        %{test_name: "renders", flow: home_mount_cycle() ++ home_mount_cycle()}
      ])

    assert Enum.map(normalized.canonical_flow, & &1.node_id) == [
             "Demo.Web.HomeLive",
             "Demo.Game",
             "Demo.Bonus"
           ]

    assert length(normalized.raw_flow) == 6
    assert [%{test_name: "renders", flow: flow}] = normalized.test_flows
    assert length(flow) == 3
  end

  test "canonical aggregation keeps the richest unique normalized page flow" do
    normalized =
      normalize([
        %{test_name: "load", flow: game_flow("load", ["Demo.Game", "Demo.Wallet"])},
        %{
          test_name: "play",
          flow: game_flow("play", ["Demo.Game", "Demo.Wallet", "Demo.Session"])
        },
        %{
          test_name: "play duplicate",
          flow: game_flow("play duplicate", ["Demo.Game", "Demo.Wallet", "Demo.Session"])
        }
      ])

    assert Enum.map(normalized.canonical_flow, & &1.node_id) == [
             "Demo.Web.GameLive",
             "Demo.Game",
             "Demo.Wallet",
             "Demo.Session"
           ]
  end

  test "upgrades coarse page resource reads to exact action nodes when metadata is unambiguous" do
    normalized =
      normalize([
        %{
          test_name: "sign in",
          flow: [
            page_entry("Demo.Web.AuthLive", "sign in"),
            app_read("Demo.User", "sign in", capture_origin: "ash_tracer")
          ]
        }
      ])

    assert Enum.map(normalized.canonical_flow, & &1.focus_node_id) == [
             "Demo.Web.AuthLive",
             "Demo.User:action:sign_in_with_password"
           ]
  end

  test "suppresses helper observation reads from canonical page flow but preserves raw evidence" do
    normalized =
      normalize([
        %{
          test_name: "submit",
          flow: [
            page_entry("Demo.Web.WithdrawalLive", "submit"),
            step(%{
              node_id: "Demo.WithdrawalRequest",
              focus_node_id: "Demo.WithdrawalRequest:action:create",
              kind: :action_execute,
              action: "create",
              capture_origin: "ash_tracer",
              test_name: "submit"
            }),
            helper_read("Demo.WithdrawalRequest", "submit")
          ]
        }
      ])

    assert Enum.map(normalized.canonical_flow, & &1.focus_node_id) == [
             "Demo.Web.WithdrawalLive",
             "Demo.WithdrawalRequest:action:create"
           ]

    assert length(normalized.raw_flow) == 3
    assert [%{flow: test_flow}] = normalized.test_flows

    assert Enum.map(test_flow, & &1.focus_node_id) == [
             "Demo.Web.WithdrawalLive",
             "Demo.WithdrawalRequest:action:create"
           ]
  end

  test "preserves real repeated user actions on the same page" do
    normalized =
      normalize([
        %{
          test_name: "repeat",
          flow: [
            page_entry("Demo.Web.GameLive", "repeat"),
            app_read("Demo.Session", "repeat", focus_node_id: "Demo.Session:action:read"),
            app_read("Demo.Session", "repeat", focus_node_id: "Demo.Session:action:read")
          ]
        }
      ])

    assert Enum.map(normalized.canonical_flow, & &1.focus_node_id) == [
             "Demo.Web.GameLive",
             "Demo.Session:action:read",
             "Demo.Session:action:read"
           ]
  end

  test "retains distinct normalized per-test flows before canonical aggregation" do
    normalized =
      normalize([
        %{test_name: "wallet", flow: game_flow("wallet", ["Demo.Game", "Demo.Wallet"])},
        %{test_name: "session", flow: game_flow("session", ["Demo.Game", "Demo.Session"])}
      ])

    assert Enum.map(normalized.test_flows, & &1.test_name) == ["wallet", "session"]

    assert Enum.map(Enum.at(normalized.test_flows, 0).flow, & &1.node_id) == [
             "Demo.Web.GameLive",
             "Demo.Game",
             "Demo.Wallet"
           ]

    assert Enum.map(Enum.at(normalized.test_flows, 1).flow, & &1.node_id) == [
             "Demo.Web.GameLive",
             "Demo.Game",
             "Demo.Session"
           ]
  end

  defp normalize(test_flows) do
    PageTraceNormalizer.normalize(test_flows, lookup())
  end

  defp home_mount_cycle do
    [
      page_entry("Demo.Web.HomeLive", "renders"),
      app_read("Demo.Game", "renders"),
      app_read("Demo.Bonus", "renders")
    ]
  end

  defp game_flow(test_name, nodes) do
    ["Demo.Web.GameLive" | nodes]
    |> Enum.with_index()
    |> Enum.map(fn
      {"Demo.Web.GameLive", _index} -> page_entry("Demo.Web.GameLive", test_name)
      {node_id, _index} -> app_read(node_id, test_name)
    end)
  end

  defp page_entry(node_id, test_name) do
    step(%{
      node_id: node_id,
      focus_node_id: node_id,
      kind: :entry,
      capture_origin: "live_view_mount",
      test_name: test_name
    })
  end

  defp app_read(node_id, test_name, attrs \\ []) do
    step(
      Map.merge(
        %{
          node_id: node_id,
          focus_node_id: node_id,
          kind: :read,
          type: :observation,
          capture_origin: "ash_tracer",
          test_name: test_name
        },
        Map.new(attrs)
      )
    )
  end

  defp helper_read(node_id, test_name) do
    step(%{
      node_id: node_id,
      focus_node_id: node_id,
      kind: :read,
      type: :observation,
      capture_origin: "automatic",
      test_name: test_name
    })
  end

  defp lookup do
    %Lookup{
      by_id: %{
        "Demo.Web.HomeLive" => %{id: "Demo.Web.HomeLive", type: "page", calls_actions: []},
        "Demo.Web.GameLive" => %{id: "Demo.Web.GameLive", type: "page", calls_actions: []},
        "Demo.Web.AuthLive" => %{
          id: "Demo.Web.AuthLive",
          type: "page",
          calls_actions: [
            %{
              "resource" => "Demo.User",
              "action" => :read,
              "action_name" => "sign_in_with_password"
            }
          ]
        },
        "Demo.Web.WithdrawalLive" => %{
          id: "Demo.Web.WithdrawalLive",
          type: "page",
          calls_actions: []
        },
        "Demo.Game" => %{id: "Demo.Game", type: "resource"},
        "Demo.Bonus" => %{id: "Demo.Bonus", type: "resource"},
        "Demo.Wallet" => %{id: "Demo.Wallet", type: "resource"},
        "Demo.Session" => %{id: "Demo.Session", type: "resource"},
        "Demo.User" => %{id: "Demo.User", type: "resource"},
        "Demo.WithdrawalRequest" => %{id: "Demo.WithdrawalRequest", type: "resource"}
      }
    }
  end

  defp step(attrs) do
    Step.new(
      Map.merge(
        %{
          type: :entry,
          kind: :action_execute,
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
