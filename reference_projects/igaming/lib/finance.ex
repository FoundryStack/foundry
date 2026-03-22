defmodule IgamingRef.Finance do
  @moduledoc """
  Finance domain: handles wallets, transactions, and financial operations.

  Resources:
    - Wallet
    - LedgerEntry
    - WithdrawalRequest
    - Transfer
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain]

  resources do
    resource IgamingRef.Finance.Wallet
    resource IgamingRef.Finance.LedgerEntry
    resource IgamingRef.Finance.WithdrawalRequest
    resource IgamingRef.Finance.Transfer
  end
end
