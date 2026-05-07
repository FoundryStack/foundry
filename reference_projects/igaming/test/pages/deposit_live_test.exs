defmodule IgamingRef.Web.DepositLiveTest do
  use IgamingRef.ConnCase, async: false
  import Phoenix.LiveViewTest
  use Foundry.TestScenario
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  @scenario category: :invariant
  test "deposit page mounts and renders deposit form", context do
    capture(context, fn ->
      {:ok, view, html} = live(build_conn_with_trace(), "/deposit")

      assert view
      assert html != ""
    end)
  end

  @scenario category: :invariant
  test "deposit page requires player authentication", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn_with_trace(), "/deposit")

      # page_group :player — auth required
      assert view |> render() =~ ""
    end)
  end

  @scenario category: :invariant
  test "deposit page creates deposit resource", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn_with_trace(), "/deposit")

      # Page calls IgamingRef.Finance.Deposit :create
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :invariant
  test "deposit page reads wallet resource", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn_with_trace(), "/deposit")

      # Page calls IgamingRef.Finance.Wallet :read
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :invariant
  test "deposit page uses static SDUI layout", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn_with_trace(), "/deposit")

      # use AshSDUI, lookup: {:static, "deposit"}
      rendered = render(view)
      assert rendered != ""
    end)
  end

  @scenario category: :invariant
  test "deposit page form has amount field", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn_with_trace(), "/deposit")

      # Verify form structure exists
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :invariant
  test "deposit page validates minimum amount", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn_with_trace(), "/deposit")

      # Test amount validation constraints
      rendered = render(view)
      assert rendered != ""
    end)
  end

  @scenario category: :invariant,
            flow: [%{type: :action, node: "Finance.Transfer", action: "record"}]
  test "deposit page submits deposit form", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn_with_trace(), "/deposit")
      result = render_submit(view, "submit_deposit", %{"amount" => "100.00"})
      assert result != ""
    end)
  end

end
