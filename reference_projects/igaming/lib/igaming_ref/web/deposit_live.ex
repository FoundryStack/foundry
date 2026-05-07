defmodule IgamingRef.Web.DepositLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "deposit"}
  require Ash.Query

  alias IgamingRef.Web.PreviewSupport

  @page_group :player

  @moduledoc "DepositLive - #{@page_group} page"

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
  def handle_event("submit_deposit", %{"amount" => amount}, socket) do
    with {:ok, parsed_amount} <- parse_amount(socket.assigns.wallet, amount),
         {:ok, _deposit} <-
           Ash.create(
             IgamingRef.Finance.Transfer,
             %{
               to_wallet_id: socket.assigns.wallet.id,
               amount: parsed_amount,
               reason: "deposit"
             },
             action: :record
           ) do
        {:noreply, socket |> put_flash(:info, "Deposit successful")}
    else
      _ ->
        {:noreply, socket |> put_flash(:error, "Deposit failed")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Deposit Funds</h1>
    <div :if={@flash[:info]} role="status">{@flash[:info]}</div>
    <div :if={@flash[:error]} role="alert">{@flash[:error]}</div>
    <p>Current balance: {format_money(@wallet.balance)}</p>
    <form phx-submit="submit_deposit">
      <input name="amount" type="number" step="0.01" placeholder="Amount" />
      <button type="submit">Deposit</button>
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
