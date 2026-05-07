defmodule IgamingRef.Web.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>IgamingRef Preview</title>
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
