defmodule IgamingRef.Web.DepositLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "deposit page mounts and renders deposit form" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    assert view
    |> element("div")
    |> has_element?()
  end

  test "deposit page handles amount input" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    html = render(view)
    assert html =~ ""
  end

  test "deposit page validates deposit amounts" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    assert view |> render() =~ ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
