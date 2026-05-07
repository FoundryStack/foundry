defmodule IgamingRef.Web.AuthLive do
  use Phoenix.LiveView

  @page_group :anonymous

  @moduledoc "AuthLive - #{@page_group} page"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("login", %{"email" => email, "password" => password}, socket) do
    case Ash.create(IgamingRef.Accounts.Token, %{email: email, password: password}) do
      {:ok, _token} ->
        {:noreply, socket |> redirect(to: "/")}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Invalid credentials")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Login</h1>
    <form phx-submit="login">
      <input name="email" type="email" placeholder="Email" />
      <input name="password" type="password" placeholder="Password" />
      <button type="submit">Sign In</button>
    </form>
    """
  end
end
