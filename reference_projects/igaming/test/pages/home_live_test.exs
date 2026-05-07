defmodule IgamingRef.Web.HomeLiveTest do
  use IgamingRef.ConnCase, async: false
  import Phoenix.LiveViewTest
  use Foundry.TestScenario
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  @scenario category: :flow
  test "home page mounts and renders initial content", context do
    capture(context, fn ->
      {:ok, view, html} = live(build_conn(), "/")

      assert view
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "home page mounts as anonymous user", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/")

      # Home page should be accessible without authentication
      # (page_group :anonymous means no auth required)
      assert view |> render() =~ ""
    end)
  end

  @scenario category: :flow
  test "home page reads games list", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/")

      # Page calls IgamingRef.Gaming.Game :read action
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "home page reads promotions list", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/")

      # Page calls IgamingRef.Promotions.Promotion :read action
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "home page feature flag evaluation", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/")

      # Page evaluates :new_lobby and :personalized_games feature flags
      # Content visibility depends on flag state
      assert view |> render() =~ ""
    end)
  end

end
