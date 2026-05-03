defmodule AshSDUI.Test.SampleTestComponent do
  use AshSDUI.Component,
    fragment: """
    fragment SampleData on User {
      username
    }
    """

  def render(assigns) do
    {:safe, "<div>#{assigns[:subject]}</div>"}
  end
end
