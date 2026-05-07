defmodule IgamingRef.Web.ErrorView do
  use Phoenix.View,
    root: "lib/igaming_ref/web/templates",
    namespace: IgamingRef.Web

  def render("500.html", _assigns) do
    "Internal Server Error"
  end

  def render(_template, _assigns) do
    "Error"
  end
end
