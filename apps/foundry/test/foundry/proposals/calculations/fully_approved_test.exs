defmodule Foundry.Proposals.Calculations.FullyApprovedTest do
  use ExUnit.Case, async: true

  alias Foundry.Proposals.Calculations.FullyApproved

  defp slot, do: %{approver: "a@x.com", approver_role: :developer, approved_at: DateTime.utc_now()}

  defp record(change_class, slot_1, slot_2) do
    %{change_class: change_class, approval_slot_1: slot_1, approval_slot_2: slot_2}
  end

  describe "sensitive proposals" do
    test "false when both slots are nil" do
      assert [false] = FullyApproved.calculate([record(:sensitive, nil, nil)], [], %{})
    end

    test "false when only slot_1 is filled" do
      assert [false] = FullyApproved.calculate([record(:sensitive, slot(), nil)], [], %{})
    end

    test "true when both slots are filled" do
      assert [true] = FullyApproved.calculate([record(:sensitive, slot(), slot())], [], %{})
    end
  end

  describe "non-sensitive proposals" do
    for class <- [:structural, :behavioral, :compliance] do
      test "#{class}: false when slot_1 is nil" do
        assert [false] = FullyApproved.calculate([record(unquote(class), nil, nil)], [], %{})
      end

      test "#{class}: true when slot_1 is filled (slot_2 irrelevant)" do
        assert [true] = FullyApproved.calculate([record(unquote(class), slot(), nil)], [], %{})
      end
    end
  end

  test "calculates a batch of mixed records correctly" do
    records = [
      record(:sensitive, slot(), slot()),
      record(:sensitive, slot(), nil),
      record(:structural, slot(), nil),
      record(:structural, nil, nil)
    ]

    assert [true, false, true, false] = FullyApproved.calculate(records, [], %{})
  end
end
