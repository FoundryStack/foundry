defmodule IgamingRef.Web.GameLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:from_params, :name}

  alias IgamingRef.Web.PreviewSupport

  @page_group :player

  @moduledoc "GameLive - #{@page_group} page"

  @impl true
  def mount(params, _session, socket) do
    player_id = socket.assigns[:player_id] || PreviewSupport.sample_player_id()
    game_id = Map.get(params, "id", "preview")

    game =
      PreviewSupport.safe_read(
        fn -> Ash.read_one!(IgamingRef.Gaming.Game, filter: [id: game_id]) end,
        PreviewSupport.sample_game(game_id)
      )
    Foundry.TestScenario.RuntimeCapture.trace_node("IgamingRef.Gaming.Game", action_kind: :read)

    wallet =
      PreviewSupport.safe_read(
        fn -> Ash.read_one!(IgamingRef.Finance.Wallet, filter: [player_id: player_id]) end,
        PreviewSupport.sample_wallet()
      )
    Foundry.TestScenario.RuntimeCapture.trace_node("IgamingRef.Finance.Wallet", action_kind: :read)

    {:ok, assign(socket, game: game, wallet: wallet, player_id: player_id, session: nil)}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    case Ash.create(IgamingRef.Gaming.GameSession, :start, %{
           player_id: socket.assigns.player_id,
           game_id: socket.assigns.game.id
         }) do
      {:ok, game_session} ->
        Foundry.TestScenario.RuntimeCapture.trace_node("IgamingRef.Gaming.GameSession", action_kind: :create)
        {:noreply, assign(socket, session: game_session)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not start session")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>{@game.name}</h1>
    <p>Balance: {@wallet.balance}</p>
    <button phx-click="start_game">Play</button>
    """
  end
end
