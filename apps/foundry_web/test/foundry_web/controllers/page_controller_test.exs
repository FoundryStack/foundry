defmodule FoundryWeb.PageControllerTest do
  use FoundryWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET /preview-launch renders redirect shell for preview target", %{conn: conn} do
    conn = get(conn, ~p"/preview-launch?base=http://localhost:4001&route=/games")
    html = html_response(conn, 200)

    assert html =~ "Starting preview"
    assert html =~ "http://localhost:4001/games"
  end
end
