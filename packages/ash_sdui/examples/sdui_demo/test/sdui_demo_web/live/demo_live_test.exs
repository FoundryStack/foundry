defmodule SduiDemoWeb.Live.DemoLiveTest do
  use SduiDemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    # Initialize registry
    AshSDUI.Registry.init_table()

    # Create a test user (will be the first and only user in the ETS table)
    {:ok, user} =
      SduiDemo.Accounts.User
      |> Ash.Changeset.for_create(:create, %{
        username: "test_user",
        email: "test@example.com",
        avatar_url: "https://example.com/test.jpg"
      })
      |> Ash.create()

    {:ok, user: user}
  end

  describe "demo_live renders components" do
    test "renders root TwoColumnLayout component", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Verify the layout structure is present
      assert html =~ "two-column-layout"
      assert html =~ "sidebar"
      assert html =~ "main-content"
    end

    test "renders ActionButton in main region", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Verify ActionButton is rendered with proper class and content
      assert html =~ "action-button"
      assert html =~ "Click"
    end

    test "renders nested components with proper HTML structure", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Verify proper nesting with opening and closing tags
      assert html =~ ~s(<div class="two-column-layout")
      assert html =~ ~s(<aside class="sidebar">)
      assert html =~ ~s(<main class="main-content">)
      assert html =~ ~s(</aside>)
      assert html =~ ~s(</main>)
    end

    test "renders UserCard with loaded user data", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Verify UserCard is rendered
      assert html =~ "user-card"

      # Verify user data is loaded (not showing "No user loaded")
      refute html =~ "No user loaded"

      # The demo layout resolves the first available user for display
      assert html =~ "_user"
      assert html =~ "@example.com"
    end
  end
end
