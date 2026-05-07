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
    query =
      Ash.Query.for_read(IgamingRef.Accounts.User, :sign_in_with_password, %{
        email: email,
        password: password
      })

    case Ash.read_one(query, authorize?: false) do
      {:ok, %{} = _user} ->
        {:noreply, socket |> redirect(to: "/")}

      _ ->
        {:noreply, socket |> put_flash(:error, "Invalid credentials")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Login</h1>
    <div :if={@flash[:error]} role="alert">{@flash[:error]}</div>
    <form phx-submit="login">
      <input name="email" type="email" placeholder="Email" />
      <input name="password" type="password" placeholder="Password" />
      <button type="submit">Sign In</button>
    </form>
    """
  end
end
