defmodule IgamingRef.Web.WithdrawalLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "withdrawal"}

  @page_group :player
  @calls_actions [
    {IgamingRef.Finance.Withdrawal, :create},
    {IgamingRef.Finance.Wallet, :read},
    {IgamingRef.Finance.WithdrawalRule, :read}
  ]

  @moduledoc "WithdrawalLive - #{@page_group} page"

  @impl true
  def mount(_params, _session, socket) do
    rules = Ash.read!(IgamingRef.Finance.WithdrawalRule)
    {:ok, socket |> assign(rules: rules)}
  end

  @impl true
  def handle_event("submit_withdrawal", %{"amount" => amount}, socket) do
    case Ash.create(IgamingRef.Finance.Withdrawal,
           input: %{
             user_id: socket.assigns.user_id,
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
    <ul>
      <%= for rule <- @rules do %>
        <li><%= rule.name %></li>
      <% end %>
    </ul>
    <form phx-submit="submit_withdrawal">
      <input name="amount" type="number" step="0.01" placeholder="Amount" />
      <button type="submit">Withdraw</button>
    </form>
    """
  end
end
