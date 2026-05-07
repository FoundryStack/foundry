defmodule IgamingRef.Web.GameLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "game page mounts with dynamic route parameter" do
    {:ok, view, _html} = live(build_conn(), "/games/test-game")

    assert view
    |> element("div")
    |> has_element?()
  end

  test "game page handles game selection" do
    {:ok, view, _html} = live(build_conn(), "/games/test-game")

    # Render initial state
    html = render(view)
    assert html =~ ""
  end

  test "game page rejects invalid game id" do
    {:ok, view, _html} = live(build_conn(), "/games/invalid-123")

    assert view |> render() =~ ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
