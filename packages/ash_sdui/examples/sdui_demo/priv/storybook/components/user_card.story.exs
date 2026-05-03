defmodule SduiDemoWeb.Storybook.Components.UserCard do
  use PhoenixStorybook.Story, :component

  def function, do: &SduiDemoWeb.Components.UserCard.render/1

  def variations do
    [
      %PhoenixStorybook.Story.Variation{
        id: :with_user,
        description: "UserCard with a mock user subject",
        attributes: %{
          subject: %{username: "alice", avatar_url: "https://placekitten.com/64/64", email: "alice@example.com"},
          props: %{},
          region: :sidebar,
          children: %{}
        }
      },
      %PhoenixStorybook.Story.Variation{
        id: :no_user,
        description: "UserCard with nil subject",
        attributes: %{
          subject: nil,
          props: %{},
          region: :sidebar,
          children: %{}
        }
      }
    ]
  end
end
