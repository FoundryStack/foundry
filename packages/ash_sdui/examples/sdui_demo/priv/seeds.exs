alias SduiDemo.Accounts.User

# Create demo user
case User
     |> Ash.Changeset.for_create(:create, %{
       username: "demo_user",
       email: "demo@example.com",
       avatar_url: "https://api.example.com/avatars/demo.jpg"
     })
     |> Ash.create() do
  {:ok, user} ->
    IO.puts("✓ Created demo user: #{user.id}")

  {:error, reason} ->
    IO.inspect(reason, label: "Error creating user")
end
