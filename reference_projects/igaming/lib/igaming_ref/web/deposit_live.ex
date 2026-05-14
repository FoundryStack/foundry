defmodule IgamingRef.Web.DepositLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "deposit"}
  require Ash.Query
  require Logger

  alias IgamingRef.Finance.DepositTransfer
  alias IgamingRef.Finance.Wallet
  alias IgamingRef.Web.PreviewSupport

  @page_group :player

  @moduledoc "DepositLive - #{@page_group} page"

  @impl true
  def mount(_params, session, socket) do
    player_id = session_player_id(session)
    preview? = is_nil(player_id)
    player_id = player_id || PreviewSupport.sample_player_id()
    Logger.info("DepositLive.mount: preview?=#{preview?}, player_id=#{player_id}")

    wallet =
      if preview? do
        # In preview mode, restore wallet from session if available, otherwise use fresh sample
        session_wallet = Map.get(session, "preview_wallet")
        session_wallet || PreviewSupport.sample_wallet()
      else
        PreviewSupport.safe_read(
          fn ->
            IgamingRef.Finance.Wallet
            |> Ash.Query.filter(player_id: player_id)
            |> Ash.read_one!(actor: %{is_system: true})
          end,
          PreviewSupport.sample_wallet()
        )
      end

    {:ok,
     assign(socket,
       wallet: wallet,
       player_id: player_id,
       preview?: preview?,
       deposit_intent_id: Ash.UUID.generate()
     )}
  end

  @impl true
  def handle_event("submit_deposit", %{"amount" => amount}, socket) do
    Logger.info("DepositLive.handle_event/3: submit_deposit called with amount=#{amount}")

    case parse_amount(socket.assigns.wallet, amount) do
      {:ok, parsed_amount} ->
        if socket.assigns.preview? do
          Logger.info(
            "DepositLive: preview mode - simulating deposit of #{inspect(parsed_amount)}"
          )

          updated_wallet = update_wallet_balance(socket.assigns.wallet, parsed_amount)
          PreviewSupport.save_preview_wallet(updated_wallet.id, updated_wallet)

          Logger.info(
            "DepositLive: saved updated preview wallet with new balance = #{inspect(updated_wallet.balance)}"
          )

          {:noreply,
           socket
           |> assign(wallet: updated_wallet)
           |> put_flash(:info, "Deposit successful (preview)")}
        else
          handle_real_deposit(socket, parsed_amount)
        end

      {:error, :invalid_amount} ->
        Logger.warning("DepositLive: deposit failed - invalid_amount")
        {:noreply, socket |> put_flash(:error, "Invalid amount")}
    end
  end

  defp handle_real_deposit(socket, parsed_amount) do
    case Reactor.run(
           DepositTransfer,
           %{
             wallet_id: socket.assigns.wallet.id,
             amount: parsed_amount,
             deposit_intent_id: socket.assigns.deposit_intent_id
           },
           %{},
           async?: false
         ) do
      {:ok, _result} ->
        case Ash.get(Wallet, socket.assigns.wallet.id, actor: %{is_system: true}) do
          {:ok, updated_wallet} ->
            Logger.info(
              "DepositLive: deposit successful, new balance = #{inspect(updated_wallet.balance)}"
            )

            {:noreply,
             socket
             |> assign(wallet: updated_wallet)
             |> put_flash(:info, "Deposit successful")}

          {:error, error} ->
            Logger.warning(
              "DepositLive: deposit succeeded but wallet reload failed - #{inspect(error)}"
            )

            {:noreply, socket |> put_flash(:error, "Deposit failed")}
        end

      {:error, %Ash.Error.Invalid{} = error} ->
        message = error.errors |> Enum.map(& &1.message) |> Enum.join(", ")
        Logger.warning("DepositLive: deposit failed - Ash error: #{message}")
        {:noreply, socket |> put_flash(:error, message)}

      {:error, error} ->
        Logger.warning("DepositLive: deposit failed - #{inspect(error)}")
        {:noreply, socket |> put_flash(:error, "Deposit failed")}
    end
  end

  defp update_wallet_balance(wallet, amount) do
    current_balance = wallet.balance || Money.new!(0, :GBP)
    new_balance = Money.add!(current_balance, amount)
    Map.put(wallet, :balance, new_balance)
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

  defp parse_amount(wallet, amount) when is_binary(amount) do
    Logger.debug("DepositLive.parse_amount: parsing amount=#{amount}")
    currency = wallet_currency(wallet)
    atom_currency = String.to_existing_atom(currency)

    result =
      case Money.new(amount, atom_currency) do
        {:ok, money} ->
          Logger.debug(
            "DepositLive.parse_amount: successfully parsed #{amount} as #{inspect(money)}"
          )

          {:ok, money}

        {:error, _} ->
          Logger.warning("DepositLive.parse_amount: invalid_amount for #{amount}")
          {:error, :invalid_amount}

        money when is_struct(money, Money) ->
          Logger.debug("DepositLive.parse_amount: got Money struct directly #{inspect(money)}")
          {:ok, money}

        _ ->
          Logger.warning("DepositLive.parse_amount: unexpected return type for #{amount}")
          {:error, :invalid_amount}
      end

    result
  rescue
    e ->
      Logger.warning("DepositLive.parse_amount: exception #{inspect(e)}")
      {:error, :invalid_amount}
  end

  defp parse_amount(_, _), do: {:error, :invalid_amount}

  defp wallet_currency(%{currency: currency}) when is_binary(currency), do: currency
  defp wallet_currency(%{balance: %{currency: currency}}), do: Atom.to_string(currency)
  defp wallet_currency(_wallet), do: "GBP"

  defp format_money(value), do: to_string(value)

  defp session_player_id(session) when is_map(session) do
    Map.get(session, "player_id") || Map.get(session, :player_id)
  end

  defp session_player_id(_session), do: nil
end
