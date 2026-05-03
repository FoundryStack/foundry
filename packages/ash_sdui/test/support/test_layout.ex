defmodule AshSDUI.Test.TestLayout do
  alias AshSDUI.Layout

  def init_layouts do
    header_node = %Layout.Node{
      id: :header,
      component: "UserProfile.Header@v1",
      bind_subject: :self,
      region: :sidebar,
      order: 0,
      children: []
    }

    body_node = %Layout.Node{
      id: :body,
      component: "Betting.ActiveBets@v1",
      bind_subject: :bets,
      region: :main,
      order: 1,
      children: []
    }

    root_node = %Layout.Node{
      id: :root,
      component: "Layouts.TwoColumn@v1",
      bind_subject: :self,
      region: :default,
      order: 0,
      children: [header_node, body_node]
    }

    layout = %Layout.LayoutDef{
      name: "test-dashboard",
      root: root_node
    }

    Layout.register("test-dashboard", layout)
  end
end
