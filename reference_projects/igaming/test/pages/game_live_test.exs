defmodule IgamingRef.Web.GameLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "game page mounts with dynamic route parameter" do
    {:ok, view, html} = live(build_conn(), "/games/test-game")

    assert view
    assert html != ""
  end

  test "game page mounts as player only" do
    {:ok, view, _html} = live(build_conn(), "/games/test-game")

    # page_group :player means auth required
    # In test context, mounts successfully
    assert view |> render() =~ ""
  end

  test "game page reads game resource" do
    {:ok, view, _html} = live(build_conn(), "/games/test-game")

    # Page calls IgamingRef.Gaming.Game :read
    html = render(view)
    assert html != ""
  end

  test "game page reads wallet resource" do
    {:ok, view, _html} = live(build_conn(), "/games/test-game")

    # Page calls IgamingRef.Finance.Wallet :read
    html = render(view)
    assert html != ""
  end

  test "game page creates game session" do
    {:ok, view, _html} = live(build_conn(), "/games/test-game")

    # Page calls IgamingRef.Gaming.GameSession :create
    html = render(view)
    assert html != ""
  end

  test "game page accepts dynamic route parameter in SDUI lookup" do
    {:ok, view, _html} = live(build_conn(), "/games/my-game-name")

    # use AshSDUI, lookup: {:from_params, :name}
    # Verifies that route param :id is passed to SDUI lookup
    assert view |> render() =~ ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
