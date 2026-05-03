defmodule SduiDemoWeb.Storybook.Components.ActionButton do
  use PhoenixStorybook.Story, :component

  def function, do: &SduiDemoWeb.Components.ActionButton.render/1

  def variations do
    [
      %PhoenixStorybook.Story.Variation{
        id: :default,
        description: "ActionButton with label and url",
        attributes: %{
          subject: nil,
          props: %{"label" => "Go to Dashboard", "url" => "/dashboard"},
          region: :main,
          children: %{}
        }
      }
    ]
  end
end
