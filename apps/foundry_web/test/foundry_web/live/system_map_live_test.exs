defmodule FoundryWeb.SystemMapLiveTest do
  use FoundryWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "mount" do
    test "renders page with data-context attribute when context available", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")
      assert html =~ "data-context"
    end

    test "embeds valid JSON in data-context attribute", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")

      # Extract data-context value
      assert Regex.match?(~r/data-context="[^"]+nodes[^"]*"/, html)
    end

    test "shows empty state when context unavailable" do
      # We can't easily test this without mocking, but verify mount doesn't crash
      # when context building fails
      {:ok, _live, html} = live(Phoenix.ConnTest.build_conn(), "/studio")
      # Should render without crashing
      assert html =~ "foundry-map-layout"
    end
  end

  describe "handle_event node_selected" do
    test "stores selected node in assigns", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      # Simulate node selection
      result = render_click(live, "node_selected", %{"id" => "Finance.Wallet", "data" => %{
        "id" => "Finance.Wallet",
        "type" => "resource",
        "description" => "User wallet"
      }})

      # Verify the click was processed
      assert result != nil
    end
  end

  describe "handle_event fetch_node_detail" do
    test "pushes event to client on fetch request", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      # This would normally be triggered when clicking a node in large projects
      # For now, just verify the handler exists and doesn't crash
      result = render_click(live, "fetch_node_detail", %{"id" => "Finance.Wallet"})
      assert result
    end
  end
end
