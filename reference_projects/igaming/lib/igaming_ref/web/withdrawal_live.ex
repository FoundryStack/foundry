defmodule IgamingRef.Web.WithdrawalLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "withdrawal"}

  @page_group :player
  @calls_actions [
    {IgamingRef.Finance.WithdrawalRequest, :create},
    {IgamingRef.Finance.Wallet, :read}
  ]

  @moduledoc "WithdrawalLive - #{@page_group} page"

  @impl true
  def mount(_params, _session, socket) do
    wallet = Ash.read_one!(IgamingRef.Finance.Wallet, filter: [player_id: socket.assigns.player_id])
    {:ok, assign(socket, wallet: wallet)}
  end

  @impl true
  def handle_event("submit_withdrawal", %{"amount" => amount}, socket) do
    case Ash.create(IgamingRef.Finance.WithdrawalRequest,
           input: %{
             player_id: socket.assigns.player_id,
             amount: Decimal.new(amount)
           }
         ) do
      {:ok, _withdrawal} ->
        {:noreply, socket |> put_flash(:info, "Withdrawal requested")}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Withdrawal failed")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Withdraw Funds</h1>
    <p>Available balance: <%= @wallet.balance %></p>
    <form phx-submit="submit_withdrawal">
      <input name="amount" type="number" step="0.01" placeholder="Amount" />
      <button type="submit">Withdraw</button>
    </form>
    """
  end
end
