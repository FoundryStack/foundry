defmodule SduiDemoWeb.Storybook do
  use PhoenixStorybook,
    otp_app: :sdui_demo,
    content_path: Path.expand("../../priv/storybook", __DIR__),
    css_path: "/assets/app.css",
    js_path: "/assets/app.js"
end
