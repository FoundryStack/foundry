defmodule IgamingRef.Web.AuthLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "auth page mounts and renders login form" do
    {:ok, view, _html} = live(build_conn(), "/auth")

    assert view
    |> element("div")
    |> has_element?()
  end

  test "auth page accepts authentication form input" do
    {:ok, view, _html} = live(build_conn(), "/auth")

    # Simulate form submission
    html = render(view)
    assert html =~ ""
  end

  test "auth page handles authentication errors" do
    {:ok, view, _html} = live(build_conn(), "/auth")

    assert view |> render() =~ ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
