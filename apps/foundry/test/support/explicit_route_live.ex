defmodule Foundry.TestSupport.ExplicitRouteLive do
  @page_group :admin
  @page_route "/support/explicit"

  def declared_page_group, do: @page_group
  def declared_page_route, do: @page_route
end
