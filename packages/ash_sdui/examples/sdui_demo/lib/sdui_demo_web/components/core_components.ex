defmodule SduiDemoWeb.CoreComponents do
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  @doc false
  def focus(js \\ %JS{}, selector) do
    JS.dispatch(js, "phx:focus", to: selector)
  end
end
