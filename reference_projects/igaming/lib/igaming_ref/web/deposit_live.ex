defmodule IgamingRef.Web.DepositLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "deposit"}

  @page_group :player
  @calls_actions [{IgamingRef.Finance.Deposit, :create}, {IgamingRef.Finance.Wallet, :read}]

  @moduledoc "DepositLive - #{@page_group} page"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("submit_deposit", %{"amount" => amount}, socket) do
    case Ash.create(IgamingRef.Finance.Deposit,
           input: %{
             user_id: socket.assigns.user_id,
             amount: Decimal.new(amount)
           }
         ) do
      {:ok, _deposit} ->
        {:noreply, socket |> put_flash(:info, "Deposit successful")}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Deposit failed")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Deposit Funds</h1>
    <form phx-submit="submit_deposit">
      <input name="amount" type="number" step="0.01" placeholder="Amount" />
      <button type="submit">Deposit</button>
    </form>
    """
  end
end
