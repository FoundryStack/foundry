defmodule SduiDemoWeb.Live.DemoLive do
  use SduiDemoWeb, :live_view
  use AshSDUI, lookup: {:static, "user-dashboard"}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="demo-page">
      <h1>SDUI Demo</h1>
      <.sdui_root tree={@__sdui_tree__} />
    </div>
    """
  end
end
