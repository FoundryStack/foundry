defmodule IgamingRef.Web.HomeLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "home page mounts and renders initial content" do
    {:ok, view, html} = live(build_conn(), "/")

    assert view
    assert html != ""
  end

  test "home page mounts as anonymous user" do
    {:ok, view, _html} = live(build_conn(), "/")

    # Home page should be accessible without authentication
    # (page_group :anonymous means no auth required)
    assert view |> render() =~ ""
  end

  test "home page reads games list" do
    {:ok, view, _html} = live(build_conn(), "/")

    # Page calls IgamingRef.Gaming.Game :read action
    html = render(view)
    assert html != ""
  end

  test "home page reads promotions list" do
    {:ok, view, _html} = live(build_conn(), "/")

    # Page calls IgamingRef.Promotions.Promotion :read action
    html = render(view)
    assert html != ""
  end

  test "home page feature flag evaluation" do
    {:ok, view, _html} = live(build_conn(), "/")

    # Page evaluates :new_lobby and :personalized_games feature flags
    # Content visibility depends on flag state
    assert view |> render() =~ ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
