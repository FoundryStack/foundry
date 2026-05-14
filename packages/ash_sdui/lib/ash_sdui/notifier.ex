defmodule AshSDUI.Notifier do
  @moduledoc false
  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{resource: AshSDUI.UINode} = notification) do
    AshSDUI.Cache.evict_for_node(notification.data)
    :ok
  end

  def notify(_), do: :ok
end
