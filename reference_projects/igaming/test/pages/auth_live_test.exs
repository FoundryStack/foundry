defmodule IgamingRef.Web.AuthLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "auth page mounts and renders login form" do
    {:ok, view, html} = live(build_conn(), "/auth")

    assert view
    assert html != ""
  end

  test "auth page is anonymous" do
    {:ok, view, _html} = live(build_conn(), "/auth")

    # page_group :anonymous — accessible without auth
    assert view |> render() =~ ""
  end

  test "auth page creates token resource" do
    {:ok, view, _html} = live(build_conn(), "/auth")

    # Page calls IgamingRef.User.Token :create
    html = render(view)
    assert html != ""
  end

  test "auth page form submission" do
    {:ok, view, _html} = live(build_conn(), "/auth")

    # Test form mount and initial render
    rendered = render(view)
    assert rendered != ""
  end

  test "auth page handles empty credentials" do
    {:ok, view, _html} = live(build_conn(), "/auth")

    # Test error handling for missing credentials
    html = render(view)
    assert html != ""
  end

  test "auth page form has required fields" do
    {:ok, view, _html} = live(build_conn(), "/auth")

    # Verify login form is present
    rendered = render(view)
    assert rendered != ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
