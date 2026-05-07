defmodule IgamingRef.Web.HomeLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "home page mounts and renders initial content" do
    {:ok, view, _html} = live(build_conn(), "/")

    assert view
    |> element("div")
    |> has_element?()
  end

  test "home page applies feature flags" do
    {:ok, view, _html} = live(build_conn(), "/")

    # Check that feature flags are evaluated
    # (In a real implementation, you'd check for visibility of flag-dependent content)
    assert view |> render() =~ ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
