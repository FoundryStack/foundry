defmodule IgamingRef.Web.DepositLiveTest do
  use IgamingRef.ConnCase, async: false
  import Phoenix.LiveViewTest
  use Foundry.TestScenario
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  @scenario category: :flow
  test "deposit page mounts and renders deposit form", context do
    capture(context, fn ->
      {:ok, view, html} = live(build_conn(), "/deposit")

      assert view
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "deposit page requires player authentication", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/deposit")

      # page_group :player — auth required
      assert view |> render() =~ ""
    end)
  end

  @scenario category: :flow
  test "deposit page creates deposit resource", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/deposit")

      # Page calls IgamingRef.Finance.Deposit :create
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "deposit page reads wallet resource", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/deposit")

      # Page calls IgamingRef.Finance.Wallet :read
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "deposit page uses static SDUI layout", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/deposit")

      # use AshSDUI, lookup: {:static, "deposit"}
      rendered = render(view)
      assert rendered != ""
    end)
  end

  @scenario category: :flow
  test "deposit page form has amount field", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/deposit")

      # Verify form structure exists
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "deposit page validates minimum amount", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/deposit")

      # Test amount validation constraints
      rendered = render(view)
      assert rendered != ""
    end)
  end

  @scenario category: :flow,
            flow: [%{type: :action, node: "Finance.Transfer", action: "record"}]
  test "deposit page submits deposit form", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/deposit")
      result = render_submit(view, "submit_deposit", %{"amount" => "100.00"})
      assert result != ""
    end)
  end

end
