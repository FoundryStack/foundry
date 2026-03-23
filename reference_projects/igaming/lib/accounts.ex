defmodule IgamingRef.Accounts do
  @moduledoc """
  Accounts domain: manages authentication and user accounts.

  Resources:
    - User
    - Token
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain]

  resources do
    resource IgamingRef.Accounts.User
    resource IgamingRef.Accounts.Token
  end
end
