defmodule IgamingRef.Web.PreviewSupport do
  @moduledoc false

  def sample_player_id, do: "preview-player"

  def sample_wallet do
    %{id: "preview-wallet", balance: Money.new(:GBP, "1250.00"), currency: "GBP"}
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
