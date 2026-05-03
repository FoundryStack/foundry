defmodule SduiDemo.UI.Layouts.DashboardLayout do
  alias AshSDUI.Layout
  alias SduiDemo.Accounts.User

  def register do
    # Get the first user if available
    user_id =
      case Ash.read(User) do
        {:ok, [user | _]} -> user.id
        _ -> nil
      end

    user_card = %Layout.Node{
      id: "user-card-1",
      component: "UserCard@v1",
      bind_subject: :user,
      region: :sidebar,
      order: 0,
      subject_resource: "SduiDemo.Accounts.User",
      subject_id: user_id,
      children: []
    }

    action_btn = %Layout.Node{
      id: "action-btn-1",
      component: "ActionButton@v1",
      bind_subject: nil,
      region: :main,
      order: 0,
      children: []
    }

    root = %Layout.Node{
      id: "dashboard-root",
      component: "Layouts.TwoColumnLayout@v1",
      bind_subject: nil,
      region: :default,
      order: 0,
      children: [user_card, action_btn]
    }

    Layout.register("user-dashboard", %Layout.LayoutDef{
      name: "user-dashboard",
      root: root
    })

    IO.puts("✓ Registered user-dashboard layout (user_id: #{user_id})")
  end
end
