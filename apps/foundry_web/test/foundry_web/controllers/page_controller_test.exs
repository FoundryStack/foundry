defmodule FoundryWeb.PageControllerTest do
  use FoundryWeb.ConnCase

  test "GET /project-manager renders workspace chooser", %{conn: conn} do
    conn = get(conn, ~p"/project-manager")
    html = html_response(conn, 200)

    assert html =~ "Choose a workspace"
    assert html =~ "Open local project"
    assert html =~ "Clone Git repository"
    assert html =~ "New Project"
    assert html =~ "Recent workspaces"
  end

  test "GET /project-status returns project manager status payload", %{conn: conn} do
    conn = get(conn, ~p"/project-status")
    body = json_response(conn, 200)

    assert Map.has_key?(body, "state")
    assert Map.has_key?(body, "logs")
    assert Map.has_key?(body, "message")
  end

  test "GET /preview-launch renders redirect shell for canonical target", %{conn: conn} do
    conn = get(conn, "/preview-launch?target=http://localhost:4001/games?draft=true#hero")
    html = html_response(conn, 200)

    assert html =~ "Starting preview"
    assert html =~ "http://localhost:4001/games"
    refute html =~ "?draft=true"
    refute html =~ "#hero"
  end

  test "GET /preview-launch preserves legacy base and route params", %{conn: conn} do
    conn = get(conn, ~p"/preview-launch?base=http://localhost:4001&route=/games")
    html = html_response(conn, 200)

    assert html =~ "Starting preview"
    assert html =~ "http://localhost:4001/games"
  end

  test "GET /preview-launch falls back to default target for invalid target param", %{conn: conn} do
    conn = get(conn, "/preview-launch?target=https://example.com/games")
    html = html_response(conn, 200)

    assert html =~ "Starting preview"
    assert html =~ "http://localhost:4001/"
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

  test "GET /project-onboarding with empty folder shows deps check", %{conn: conn} do
    dir = System.tmp_dir!() |> Path.join("pm_onboard_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      conn = get(conn, ~p"/project-onboarding?path=#{dir}")
      html = html_response(conn, 200)

      assert html =~ "Dependency"
      assert html =~ "Status"
      assert html =~ "Version"
      assert html =~ "Required"
    after
      File.rm_rf!(dir)
    end
  end

  test "GET /project-onboarding with nonexistent path redirects to manager", %{conn: conn} do
    conn = get(conn, "/project-onboarding?path=/nonexistent/path_#{:rand.uniform(999)}")

    assert redirected_to(conn) == ~p"/project-manager"
  end

  test "GET /project-onboarding without path redirects to manager", %{conn: conn} do
    conn = get(conn, ~p"/project-onboarding")

    assert redirected_to(conn) == ~p"/project-manager"
  end
end
