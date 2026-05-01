defmodule FoundryWeb.ChatLiveTest do
  use FoundryWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    llm_provider = Application.get_env(:foundry, :llm_provider)
    project_root = Application.get_env(:foundry_web, :igaming_project_root)

    on_exit(fn ->
      restore_env(:foundry, :llm_provider, llm_provider)
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

  test "context build failures are shown without crashing the live view", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :claude_code)
    Application.put_env(:foundry_web, :igaming_project_root, System.tmp_dir!())

    {:ok, live, _html} = live(conn, "/chat")

    html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert html =~ "Hello"
    assert render(live) =~ "context_build_failed"
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
