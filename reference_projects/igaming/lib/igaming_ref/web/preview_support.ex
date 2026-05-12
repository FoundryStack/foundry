defmodule IgamingRef.Web.PreviewSupport do
  @moduledoc false
  @table_name :preview_wallets

  def sample_player_id, do: "preview-player"

  def sample_wallet do
    ensure_table_exists()
    case :ets.lookup(@table_name, "preview-wallet") do
      [{_key, wallet}] -> wallet
      [] ->
        wallet = %{id: "preview-wallet", balance: Money.new(:GBP, "1250.00"), currency: "GBP"}
        :ets.insert(@table_name, {"preview-wallet", wallet})
        wallet
    end
  end

  def save_preview_wallet(wallet_id, wallet) do
    ensure_table_exists()
    :ets.insert(@table_name, {wallet_id, wallet})
  end

  defp ensure_table_exists do
    if :ets.whereis(@table_name) == :undefined do
      :ets.new(@table_name, [:named_table, :public])
    end
  end

  def sample_game(game_id \\ "preview-game") do
    %{id: game_id, title: "Preview Game"}
  end

  def safe_read(fun, fallback) when is_function(fun, 0) do
    try do
      case fun.() do
        nil -> fallback
        value -> value
      end
    rescue
      _ -> fallback
    catch
      _, _ -> fallback
    end
  end
end
