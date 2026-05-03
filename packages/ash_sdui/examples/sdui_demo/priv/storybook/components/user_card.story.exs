defmodule SduiDemoWeb.Storybook.Components.UserCard do
  use PhoenixStorybook.Story, :component
  alias PhoenixStorybook.Stories.Variation

  def function, do: &SduiDemoWeb.Components.UserCard.render/1

  def variations do
    [
      %Variation{
        id: :with_user,
        description: "UserCard with a mock user subject",
        attributes: %{
          subject: %{username: "alice", avatar_url: "https://placekitten.com/64/64", email: "alice@example.com"},
          props: %{},
          region: :sidebar,
          children: %{}
        }
      },
      %Variation{
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
