defmodule IgamingRef.DataCase do
  @moduledoc """
  Shared test case for database-backed reference-project scenarios.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias IgamingRef.Repo
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(IgamingRef.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(IgamingRef.Repo, {:shared, self()})
    end

    :ok
  end
end
