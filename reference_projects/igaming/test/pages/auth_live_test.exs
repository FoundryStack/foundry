defmodule IgamingRef.Web.AuthLiveTest do
  use IgamingRef.ConnCase, async: false
  use IgamingRef.DataCase

  import Phoenix.LiveViewTest
  import Foundry.TestScenario

  alias IgamingRef.PageFixtures

  describe "auth page" do
    test "renders the login form with its active fields" do
      capture do
        {:ok, view, html} = live(build_conn_with_trace(), "/auth")

        assert html =~ "Login"
        assert has_element?(view, "form[phx-submit=login]")
        assert has_element?(view, "input[name=email][type=email]")
        assert has_element?(view, "input[name=password][type=password]")
        assert has_element?(view, "button", "Sign In")
      end
    end

    test "shows an error flash for invalid credentials" do
      capture do
        {:ok, view, _html} = live(build_conn_with_trace(), "/auth")

        view
        |> form("form", %{"email" => "missing@example.test", "password" => "wrongpass"})
        |> render_submit()

        assert PageFixtures.flash(view, :error) == "Invalid credentials"
      end
    end

    test "redirects after a successful password sign in" do
      user = PageFixtures.user_fixture()

      capture do
        {:ok, view, _html} = live(build_conn_with_trace(), "/auth")

        view
        |> form("form", %{"email" => to_string(user.email), "password" => "password123"})
        |> render_submit()

        assert_redirect(view, "/")
      end
    end
  end
end
