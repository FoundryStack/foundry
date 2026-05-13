defmodule FoundryWeb.PageControllerTest do
  use FoundryWeb.ConnCase

  test "GET /preview-launch renders redirect shell for preview target", %{conn: conn} do
    conn = get(conn, ~p"/preview-launch?base=http://localhost:4001&route=/games")
    html = html_response(conn, 200)

    assert html =~ "Starting preview"
    assert html =~ "http://localhost:4001/games"
  end

  test "GET /preview-status returns preview server status payload", %{conn: conn} do
    conn = get(conn, ~p"/preview-status")
    body = json_response(conn, 200)

    assert Map.has_key?(body, "state")
    assert Map.has_key?(body, "output")
    assert Map.has_key?(body, "last_error")
  end

  test "GET /healthz returns runtime metadata", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    body = json_response(conn, 200)

    assert body["ok"] == true
    assert body["mode"] in ["local", "standalone"]
    assert is_binary(body["version"])
  end
end
