defmodule IgamingRef.Web.WithdrawalLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "withdrawal"}
  require Ash.Query

  alias IgamingRef.Web.PreviewSupport

  @page_group :player

  @moduledoc "WithdrawalLive - #{@page_group} page"

  @impl true
  def mount(_params, _session, socket) do
    player_id = socket.assigns[:player_id] || PreviewSupport.sample_player_id()

    wallet =
      PreviewSupport.safe_read(
        fn ->
          IgamingRef.Finance.Wallet
          |> Ash.Query.filter(player_id: player_id)
          |> Ash.read_one!(actor: %{id: player_id})
        end,
        PreviewSupport.sample_wallet()
      )

    {:ok, assign(socket, wallet: wallet, player_id: player_id)}
  end

  @impl true
  def handle_event("submit_withdrawal", %{"amount" => amount}, socket) do
    wallet = socket.assigns.wallet

    with {:ok, parsed_amount} <- parse_amount(wallet, amount),
         {:ok, _withdrawal} <-
           Ash.create(
             IgamingRef.Finance.WithdrawalRequest,
             %{
               player_id: socket.assigns.player_id,
               wallet_id: wallet.id,
               amount: parsed_amount
             },
             action: :create,
             actor: %{id: socket.assigns.player_id}
           ) do
        {:noreply, socket |> put_flash(:info, "Withdrawal requested")}
    else
      _ ->
        {:noreply, socket |> put_flash(:error, "Withdrawal failed")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Withdraw Funds</h1>
    <div :if={@flash[:info]} role="status">{@flash[:info]}</div>
    <div :if={@flash[:error]} role="alert">{@flash[:error]}</div>
    <p>Available balance: {format_money(@wallet.balance)}</p>
    <form phx-submit="submit_withdrawal">
      <input name="amount" type="number" step="0.01" placeholder="Amount" />
      <button type="submit">Withdraw</button>
    </form>
    """
  end

  defp parse_amount(wallet, amount) do
    currency = wallet_currency(wallet)
    {:ok, Money.new(String.to_existing_atom(currency), amount)}
  rescue
    _ -> {:error, :invalid_amount}
  end

  defp wallet_currency(%{currency: currency}) when is_binary(currency), do: currency
  defp wallet_currency(%{balance: %{currency: currency}}), do: Atom.to_string(currency)
  defp wallet_currency(_wallet), do: "GBP"

  defp format_money(value), do: to_string(value)
end
