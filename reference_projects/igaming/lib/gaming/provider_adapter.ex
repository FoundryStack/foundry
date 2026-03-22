defmodule IgamingRef.Gaming.ProviderAdapter do
  @moduledoc """
  Behaviour for game provider adapters.

  Adapters implement integration with external game providers' APIs.
  Each adapter handles catalog sync, withdrawals, and validation.
  """

  @callback submit_withdrawal(withdrawal_request :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback retry_withdrawal(withdrawal_request :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback fetch_catalog() :: {:ok, list(map())} | {:error, term()}

  @callback validate_config(provider_config :: map()) :: :ok | {:error, term()}
end
