{:ok, users} = Ash.read(SduiDemo.Accounts.User)
IO.inspect(users, label: "Users in database")

# Try to get the first one
case users do
  [user | _] ->
    IO.inspect(user, label: "First user")
    case Ash.get(SduiDemo.Accounts.User, user.id) do
      {:ok, found_user} ->
        IO.inspect(found_user, label: "Found user by ID")
      {:error, err} ->
        IO.warn("Failed to find user: #{inspect(err)}")
    end
  [] ->
    IO.warn("No users found!")
end
