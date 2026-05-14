defmodule IgamingRef.Gaming.Adapters.PragmaticPlayV1 do
  @moduledoc """
  Provider adapter for Pragmatic Play (V1 API).

  Implements the standard provider interface for communicating with
  Pragmatic Play's legacy API endpoint. Handles game catalog syncs,
  session management, and win/loss reporting.

  Compliance: RG-MGA-006 (provider agreements)
  """

  use Foundry.Annotations

  @behaviour IgamingRef.Gaming.ProviderAdapter

  @compliance [:RG_MGA_006]
  @adapter_name "pragmatic_play_v1"

  @doc """
  Submit a withdrawal request to Pragmatic Play for processing.

  Returns: {:ok, %{reference: String.t()}} | {:error, reason}
  """
  def submit_withdrawal(withdrawal_request) do
    # In production, this would call the actual Pragmatic Play API
    {:ok, %{reference: "PP-V1-#{withdrawal_request.id}"}}
  end

  @doc """
  Retry a failed withdrawal submission.

  Returns: {:ok, %{reference: String.t()}} | {:error, reason}
  """
  def retry_withdrawal(withdrawal_request) do
    submit_withdrawal(withdrawal_request)
  end

  @doc """
  Fetch the latest game catalog from Pragmatic Play.

  Returns: {:ok, [game_data]} | {:error, reason}
  where game_data is a map with: game_code, title, category, rtp, volatility
  """
  def fetch_catalog do
    # In production, calls Pragmatic Play API
    {:ok, []}
  end

  @doc """
  Validate provider configuration.

  Returns: :ok | {:error, reason}
  """
  def validate_config(provider_config) do
    cond do
      is_nil(provider_config.api_endpoint) -> {:error, "API endpoint required"}
      is_nil(provider_config.api_key) -> {:error, "API key required"}
      true -> :ok
    end
  end
end
