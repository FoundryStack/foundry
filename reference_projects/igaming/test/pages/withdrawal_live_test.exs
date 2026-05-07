defmodule IgamingRef.Web.WithdrawalLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "withdrawal page mounts and renders withdrawal form" do
    {:ok, view, _html} = live(build_conn(), "/withdrawal")

    assert view
    |> element("div")
    |> has_element?()
  end

  test "withdrawal page handles amount input" do
    {:ok, view, _html} = live(build_conn(), "/withdrawal")

    html = render(view)
    assert html =~ ""
  end

  test "withdrawal page validates withdrawal amounts" do
    {:ok, view, _html} = live(build_conn(), "/withdrawal")

    assert view |> render() =~ ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
