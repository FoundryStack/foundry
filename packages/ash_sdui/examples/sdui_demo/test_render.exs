Application.ensure_all_started(:sdui_demo)

{:ok, _view, html} = Phoenix.LiveViewTest.live(SduiDemoWeb.ConnCase.build_conn(), "/")

IO.puts("\n=== RENDERED HTML ===\n")
IO.puts(html)
