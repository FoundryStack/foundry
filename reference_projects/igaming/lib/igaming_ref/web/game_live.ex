defmodule IgamingRef.Web.GameLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:from_params, :name}
  require Ash.Query

  alias IgamingRef.Web.PreviewSupport

  @page_group :player

  @moduledoc "GameLive - #{@page_group} page"

  @impl true
  def mount(params, session, socket) do
    player_id = session_player_id(session)
    preview? = is_nil(player_id)
    player_id = player_id || PreviewSupport.sample_player_id()
    game_id = Map.get(params, "id", "preview")

    game =
      PreviewSupport.safe_read(
        fn ->
          IgamingRef.Gaming.Game
          |> Ash.Query.filter(id: game_id)
          |> Ash.read_one!(authorize?: false)
        end,
        PreviewSupport.sample_game(game_id)
      )

    wallet =
      PreviewSupport.safe_read(
        fn ->
          IgamingRef.Finance.Wallet
          |> Ash.Query.filter(player_id: player_id)
          |> Ash.read_one!(actor: %{is_system: true})
        end,
        PreviewSupport.sample_wallet()
      )

    {:ok,
     assign(socket,
       game: game,
       wallet: wallet,
       player_id: player_id,
       preview?: preview? or game_id == "preview",
       session: nil
     )}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    case socket.assigns.preview? do
      true ->
        {:noreply, put_flash(socket, :error, "Could not start session")}

      false ->
        case IgamingRef.Gaming.GameSession
             |> Ash.Changeset.for_create(:start, %{
               player_id: socket.assigns.player_id,
               game_id: socket.assigns.game.id
             })
             |> Ash.create(actor: %{id: socket.assigns.player_id}) do
          {:ok, game_session} ->
            {:noreply,
             socket |> assign(session: game_session) |> put_flash(:info, "Game session started")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not start session")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>{game_name(@game)}</h1>
    <div :if={@flash[:info]} role="status">{@flash[:info]}</div>
    <div :if={@flash[:error]} role="alert">{@flash[:error]}</div>
    <p>Balance: {format_money(@wallet.balance)}</p>
    <p :if={@session}>Session ID: {@session.id}</p>
    <button phx-click="start_game">Play</button>
    """
  end

  defp game_name(%{title: title}) when is_binary(title), do: title
  defp game_name(%{name: name}) when is_binary(name), do: name
  defp game_name(_game), do: "Unknown Game"

  defp format_money(value), do: to_string(value)

  defp session_player_id(session) when is_map(session) do
    Map.get(session, "player_id") || Map.get(session, :player_id)
  end

  defp session_player_id(_session), do: nil
end
