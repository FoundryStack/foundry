defmodule IgamingRef.Web.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>IgamingRef Preview</title>
        <script defer phx-track-static type="text/javascript" src="/assets/phoenix.js"></script>
        <script defer phx-track-static type="text/javascript" src="/assets/phoenix_live_view.js"></script>
        <script type="text/javascript">
          window.addEventListener("DOMContentLoaded", () => {
            let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
            let liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
              params: {_csrf_token: csrfToken}
            })
            liveSocket.connect()
            window.liveSocket = liveSocket
          })
        </script>
        <style>
          body {
            font-family: Helvetica, Arial, sans-serif;
            margin: 0;
            padding: 2rem;
            background: #10151f;
            color: #f3f5f7;
          }

          main {
            max-width: 960px;
            margin: 0 auto;
          }
        </style>
      </head>
      <body>
        <main>
          {@inner_content}
        </main>
      </body>
    </html>
    """
  end
end
