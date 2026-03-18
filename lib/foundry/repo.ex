defmodule Foundry.Repo do
  use Ecto.Repo,
    otp_app: :foundry,
    adapter: Ecto.Adapters.Postgres
end
