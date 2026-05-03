defmodule SduiDemo.DemoData do
  @moduledoc false

  alias SduiDemo.Accounts.User

  @demo_user_attrs %{
    username: "demo_user",
    email: "demo@example.com",
    avatar_url: "https://api.example.com/avatars/demo.jpg"
  }

  def bootstrap do
    case ensure_demo_user() do
      {:ok, _status, _user} -> :ok
      {:error, _reason} -> :ok
    end
  end

  def ensure_demo_user do
    case Ash.read(User) do
      {:ok, []} ->
        User
        |> Ash.Changeset.for_create(:create, @demo_user_attrs)
        |> Ash.create()
        |> case do
          {:ok, user} -> {:ok, :created, user}
          {:error, reason} -> {:error, reason}
        end

      {:ok, [user | _]} ->
        {:ok, :existing, user}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def demo_user_attrs, do: @demo_user_attrs
end
