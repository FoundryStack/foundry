defmodule FoundryWeb.ChatLiveTest do
  use FoundryWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    llm_provider = Application.get_env(:foundry, :llm_provider)
    codex = Application.get_env(:foundry, :codex)
    lm_studio = Application.get_env(:foundry, :lm_studio)
    project_root = Application.get_env(:foundry_web, :igaming_project_root)

    on_exit(fn ->
      restore_env(:foundry, :llm_provider, llm_provider)
      restore_env(:foundry, :codex, codex)
      restore_env(:foundry, :lm_studio, lm_studio)
      restore_env(:foundry_web, :igaming_project_root, project_root)
    end)
  end

  test "does not send input changes for every typed character", %{conn: conn} do
    {:ok, _live, html} = live(conn, "/chat")

    refute html =~ ~s(phx-change="set_input")
  end

  test "submits the finished message only", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :unknown_provider)

    {:ok, live, _html} = live(conn, "/chat")

    html =
      render_submit(live, "send_message", %{"message" => "Hello!! Tell me about the project"})

    assert html =~ "Hello!! Tell me about the project"
    refute html =~ ~s(phx-change="set_input")
  end

  test "shows the target project system context prompt", %{conn: conn} do
    {:ok, live, html} = live(conn, "/chat")

    project_root = Application.fetch_env!(:foundry_web, :igaming_project_root)

    assert html =~ project_root
    refute html =~ "System Context Prompt"

    html = render_click(live, "toggle_system_context")

    assert html =~ "System Context Prompt"
    assert html =~ "Target project root: #{project_root}"
    assert html =~ "System Architecture"
    assert html =~ "reference iGaming project"
  end

  test "context build failures are shown without crashing the live view", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :claude_code)
    Application.put_env(:foundry_web, :igaming_project_root, System.tmp_dir!())

    {:ok, live, _html} = live(conn, "/chat")

    html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert html =~ "Hello"
    assert eventually(fn -> render(live) =~ "context_build_failed" end)
  end

  test "lm studio connection failures are shown without crashing the live view", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :lm_studio)

    Application.put_env(:foundry, :lm_studio,
      base_url: "http://127.0.0.1:1/v1",
      model: "local-model",
      timeout_ms: 200
    )

    {:ok, live, _html} = live(conn, "/chat")

    html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert html =~ "Hello"
    assert eventually(fn -> render(live) =~ "lm_studio_error" end, 120), render(live)
  end

  test "codex unavailable is shown without crashing the live view", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :codex)
    Application.put_env(:foundry, :codex, executable: "/missing/codex/for/test")

    {:ok, live, _html} = live(conn, "/chat")

    html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert html =~ "Hello"

    assert eventually(fn -> render(live) =~ "OpenAI Codex CLI is not installed" end, 120),
           render(live)
  end

  defp eventually(fun, attempts \\ 10)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
