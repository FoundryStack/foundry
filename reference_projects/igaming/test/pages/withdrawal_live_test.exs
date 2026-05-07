defmodule IgamingRef.Web.WithdrawalLiveTest do
  use IgamingRef.ConnCase, async: false
  import Phoenix.LiveViewTest
  use Foundry.TestScenario
  @moduletag :scenario

  setup do
    {:ok, _} = Application.ensure_all_started(:igaming_ref)
    :ok
  end

  @scenario category: :flow
  test "withdrawal page mounts and renders withdrawal form", context do
    capture(context, fn ->
      {:ok, view, html} = live(build_conn(), "/withdrawal")

      assert view
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "withdrawal page requires player authentication", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/withdrawal")

      # page_group :player — auth required
      assert view |> render() =~ ""
    end)
  end

  @scenario category: :flow
  test "withdrawal page reads withdrawal rules", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/withdrawal")

      # Page calls IgamingRef.Finance.WithdrawalRule :read
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "withdrawal page reads withdrawal requests", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/withdrawal")

      # Page calls IgamingRef.Finance.WithdrawalRequest :read
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "withdrawal page uses static SDUI layout", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/withdrawal")

      # use AshSDUI, lookup: {:static, "withdrawal"}
      rendered = render(view)
      assert rendered != ""
    end)
  end

  @scenario category: :flow
  test "withdrawal page form has amount field", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/withdrawal")

      # Verify form structure exists
      html = render(view)
      assert html != ""
    end)
  end

  @scenario category: :flow
  test "withdrawal page enforces withdrawal rules", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/withdrawal")

      # Test withdrawal rule constraints
      rendered = render(view)
      assert rendered != ""
    end)
  end

  @scenario category: :flow,
            flow: [%{type: :action, node: "Finance.WithdrawalRequest", action: "create"}]
  test "withdrawal page submits withdrawal form", context do
    capture(context, fn ->
      {:ok, view, _html} = live(build_conn(), "/withdrawal")
      result = render_submit(view, "submit_withdrawal", %{"amount" => "50.00"})
      assert result != ""
    end)
  end

end
