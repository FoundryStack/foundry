defmodule SduiDemoWeb.StorybookTest do
  use SduiDemoWeb.ConnCase, async: false

  test "storybook backend discovers component stories" do
    paths =
      SduiDemoWeb.Storybook.leaves()
      |> Enum.map(& &1.path)

    assert "/components/action_button" in paths
    assert "/components/user_card" in paths
  end

  test "storybook redirects to the first discovered component story", %{conn: conn} do
    conn = get(conn, "/storybook")

    assert redirected_to(conn) == "/storybook/components/action_button"
  end
end
