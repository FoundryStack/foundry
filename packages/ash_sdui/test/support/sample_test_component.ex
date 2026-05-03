defmodule AshSDUI.Test.SampleTestComponent do
  use AshSDUI.Component,
    fragment: """
    fragment SampleTestComponentData on User {
      id
    }
    """
end
