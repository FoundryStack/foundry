defmodule IgamingRef.Finance do
  @moduledoc """
  Finance domain: handles wallets, transactions, and financial operations.

  Resources:
    - Wallet
    - LedgerEntry
    - WithdrawalRequest
    - WithdrawalWebhookEvent
    - Transfer
  """

  use Ash.Domain,
    extensions: [AshArchival.Domain, AshPaperTrail.Domain],
    validate_config_inclusion?: false

  resources do
    resource(IgamingRef.Finance.Wallet)
    resource(IgamingRef.Finance.LedgerEntry)
    resource(IgamingRef.Finance.WithdrawalRequest)
    resource(IgamingRef.Finance.WithdrawalWebhookEvent)
    resource(IgamingRef.Finance.Transfer)
  end
end
