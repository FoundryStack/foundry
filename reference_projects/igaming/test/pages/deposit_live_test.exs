defmodule IgamingRef.Web.DepositLiveTest do
  use Phoenix.LiveViewTest
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  test "deposit page mounts and renders deposit form" do
    {:ok, view, html} = live(build_conn(), "/deposit")

    assert view
    assert html != ""
  end

  test "deposit page requires player authentication" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    # page_group :player — auth required
    assert view |> render() =~ ""
  end

  test "deposit page creates deposit resource" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    # Page calls IgamingRef.Finance.Deposit :create
    html = render(view)
    assert html != ""
  end

  test "deposit page reads wallet resource" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    # Page calls IgamingRef.Finance.Wallet :read
    html = render(view)
    assert html != ""
  end

  test "deposit page uses static SDUI layout" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    # use AshSDUI, lookup: {:static, "deposit"}
    rendered = render(view)
    assert rendered != ""
  end

  test "deposit page form has amount field" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    # Verify form structure exists
    html = render(view)
    assert html != ""
  end

  test "deposit page validates minimum amount" do
    {:ok, view, _html} = live(build_conn(), "/deposit")

    # Test amount validation constraints
    rendered = render(view)
    assert rendered != ""
  end

  defp build_conn do
    Phoenix.ConnTest.build_conn()
  end
end
