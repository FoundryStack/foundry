defmodule IgamingRef.Accounts do
  @moduledoc """
  Accounts domain: manages authentication and user accounts.

  Resources:
    - User
    - Token
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain],
    validate_config_inclusion?: false

  resources do
    resource IgamingRef.Accounts.User
    resource IgamingRef.Accounts.User.Version
    resource IgamingRef.Accounts.Token
    resource IgamingRef.Accounts.Token.Version
  end
end
