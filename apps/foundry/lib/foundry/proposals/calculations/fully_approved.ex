defmodule Foundry.Proposals.Calculations.FullyApproved do
  @moduledoc """
  Calculates whether all required approvals for this proposal's change_class have been recorded.
  :sensitive proposals require both slots filled; all others require only slot_1.
  """

  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.change_class do
        :sensitive -> not is_nil(record.approval_slot_1) and not is_nil(record.approval_slot_2)
        _ -> not is_nil(record.approval_slot_1)
      end
    end)
  end
end
