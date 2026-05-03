defmodule SduiDemo.Application do
  use Application

  @impl true
  def start(_type, _args) do
    AshSDUI.Registry.init_table()
    register_components()
    seed_demo_data()

    SduiDemo.UI.Layouts.DashboardLayout.register()

    children = [
      {Phoenix.PubSub, name: SduiDemo.PubSub},
      SduiDemoWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SduiDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp register_components do
    # Manually register components to handle incremental builds where
    # modules might not recompile and thus their __before_compile__ hooks don't run
    AshSDUI.Registry.register(
      "UserCard@v1",
      SduiDemoWeb.Components.UserCard,
      %{
        fragment:
          "fragment UserCardData on User {\n  username\n  avatarUrl\n}\n",
        subject_types: ["User"]
      }
    )

    AshSDUI.Registry.register(
      "ActionButton@v1",
      SduiDemoWeb.Components.ActionButton,
      %{
        fragment:
          "fragment ActionButtonData on Action {\n  label\n  url\n}\n",
        subject_types: ["Action"]
      }
    )

    AshSDUI.Registry.register(
      "Layouts.TwoColumnLayout@v1",
      SduiDemoWeb.Components.Layouts.TwoColumnLayout,
      %{
        fragment: "fragment TwoColumnLayoutData on Layout {\n  id\n}\n",
        subject_types: ["Layout"]
      }
    )
  end

  defp seed_demo_data do
    alias SduiDemo.Accounts.User

    case User |> Ash.read() do
      {:ok, []} ->
        # Only create if no users exist
        case User
             |> Ash.Changeset.for_create(:create, %{
               username: "demo_user",
               email: "demo@example.com",
               avatar_url: "https://api.example.com/avatars/demo.jpg"
             })
             |> Ash.create() do
          {:ok, _user} ->
            IO.puts("✓ Created demo user")

          {:error, _reason} ->
            nil
        end

      _ ->
        nil
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    SduiDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
