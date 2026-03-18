defmodule FoundryWeb.PageController do
  use FoundryWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
