defmodule SduiDemo.UI.Layouts.DashboardLayout do
  alias AshSDUI.Layout
  alias SduiDemo.Accounts.User

  def register do
    # Create a layout that finds the first user at render time
    # by using a marker value that resolve_subject will understand
    user_card = %Layout.Node{
      id: "user-card-1",
      component: "UserCard@v1",
      bind_subject: :user,
      region: :sidebar,
      order: 0,
      subject_resource: "SduiDemo.Accounts.User",
      subject_id: "first",
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
  end
end
