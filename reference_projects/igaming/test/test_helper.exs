ExUnit.start()
Application.ensure_all_started(:igaming_ref)

if Code.ensure_loaded?(Ecto.Adapters.SQL.Sandbox) do
  Ecto.Adapters.SQL.Sandbox.mode(IgamingRef.Repo, :manual)
end
