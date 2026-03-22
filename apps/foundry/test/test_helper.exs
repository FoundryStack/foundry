ExUnit.start()

if Code.ensure_loaded?(Ecto.Adapters.SQL.Sandbox) do
  Ecto.Adapters.SQL.Sandbox.mode(Foundry.Repo, :manual)
end
