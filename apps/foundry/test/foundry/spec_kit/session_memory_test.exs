defmodule Foundry.SpecKit.SessionMemoryTest do
  use ExUnit.Case, async: true

  alias Foundry.SpecKit.SessionMemory

  test "extract strips the hidden foundry-memory block from the visible response" do
    response = """
    Here is the answer the user should see.

    ```foundry-memory
    {"title":"Withdrawal idempotency","summary":"Idempotency must stay on the reactor boundary.","findings":["[VERIFIED] The provider callback is retried externally."]}
    ```
    """

    extracted = SessionMemory.extract(response)

    assert extracted.response == "Here is the answer the user should see."
    assert extracted.payload["title"] == "Withdrawal idempotency"
    assert extracted.error == nil
  end

  test "persist writes a canonical finding artifact under docs/findings" do
    root =
      Path.join(System.tmp_dir!(), "foundry-session-memory-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    payload = %{
      "title" => "Ledger replay hazard",
      "summary" =>
        "A replayed provider callback can double-apply without an idempotency boundary.",
      "findings" => ["[VERIFIED] The callback path re-enters the same processing flow."],
      "issues" => ["[INFERRED] Missing idempotency on the edge would duplicate ledger mutations."],
      "related_nodes" => ["Finance.WithdrawalTransfer"],
      "related_docs" => ["docs/adrs/ADR-001-double-entry-ledger.md"],
      "tags" => ["ledger", "idempotency"]
    }

    assert {:ok, artifact} =
             SessionMemory.persist(root, "session-123", payload, %{
               "mode" => "ask",
               "user_message" => "Why does this callback need idempotency?"
             })

    assert artifact.path =~ "docs/findings/FND-"

    saved = File.read!(Path.join(root, artifact.path))

    assert saved =~ "# #{artifact.id}: Ledger replay hazard"
    assert saved =~ "## Technical Findings"
    assert saved =~ "## Issues"
    assert saved =~ "## Source Request"
    assert saved =~ "Why does this callback need idempotency?"
  end
end
