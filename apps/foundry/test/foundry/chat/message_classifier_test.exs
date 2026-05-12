defmodule Foundry.Chat.MessageClassifierTest do
  use ExUnit.Case

  alias Foundry.Chat.MessageClassifier

  describe "classify_mode/1" do
    test "routes ask-override patterns to :ask" do
      assert MessageClassifier.classify_mode("review the implementation") == :ask
      assert MessageClassifier.classify_mode("explain how auth works") == :ask
      assert MessageClassifier.classify_mode("audit the payment flow") == :ask
      assert MessageClassifier.classify_mode("understand the wallet domain") == :ask
      assert MessageClassifier.classify_mode("describe the bonus engine") == :ask
      assert MessageClassifier.classify_mode("list all modules") == :ask
      assert MessageClassifier.classify_mode("check if tests pass") == :ask
      assert MessageClassifier.classify_mode("show me the system") == :ask
    end

    test "routes change patterns to :change" do
      assert MessageClassifier.classify_mode("fix the auth bug") == :change
      assert MessageClassifier.classify_mode("implement the payment module") == :change
      assert MessageClassifier.classify_mode("edit the reactor") == :change
      assert MessageClassifier.classify_mode("update the schema") == :change
      assert MessageClassifier.classify_mode("create a new domain") == :change
      assert MessageClassifier.classify_mode("add error handling") == :change
      assert MessageClassifier.classify_mode("remove the deprecated code") == :change
      assert MessageClassifier.classify_mode("delete unused functions") == :change
      assert MessageClassifier.classify_mode("rename the module") == :change
      assert MessageClassifier.classify_mode("refactor the handler") == :change
      assert MessageClassifier.classify_mode("migrate the table") == :change
      assert MessageClassifier.classify_mode("write tests for payment") == :change
      assert MessageClassifier.classify_mode("write tests") == :change
    end

    test "routes unknown to :ask" do
      assert MessageClassifier.classify_mode("how is authentication implemented?") == :ask
      assert MessageClassifier.classify_mode("what does the wallet module do?") == :ask
      assert MessageClassifier.classify_mode("tell me about the system") == :ask
    end

    test "ask overrides take precedence over change patterns" do
      assert MessageClassifier.classify_mode("review the implementation") == :ask
      assert MessageClassifier.classify_mode("explain how to implement") == :ask
    end

    test "is case-insensitive" do
      assert MessageClassifier.classify_mode("IMPLEMENT the module") == :change
      assert MessageClassifier.classify_mode("Review the code") == :ask
      assert MessageClassifier.classify_mode("FiX the bug") == :change
    end

    test "uses word boundaries to avoid substring matches" do
      # "implementation" is not a change verb
      assert MessageClassifier.classify_mode("review the implementation") == :ask
      # "fixed" contains "fix" but is not word-bounded
      assert MessageClassifier.classify_mode("this is fixed") == :ask
      # "edited" contains "edit" but is not word-bounded
      assert MessageClassifier.classify_mode("the code is edited") == :ask
    end
  end

  describe "classify_proposal_command/2" do
    test "routes apply synonyms to proposal_apply" do
      session_digest = %{"active_proposal_id" => "prop-123", "active_proposal_status" => "draft"}

      assert MessageClassifier.classify_proposal_command("approve", session_digest) ==
               {:proposal_action, "proposal_apply", "prop-123"}

      assert MessageClassifier.classify_proposal_command("apply", session_digest) ==
               {:proposal_action, "proposal_apply", "prop-123"}

      assert MessageClassifier.classify_proposal_command("confirm", session_digest) ==
               {:proposal_action, "proposal_apply", "prop-123"}

      assert MessageClassifier.classify_proposal_command("proceed", session_digest) ==
               {:proposal_action, "proposal_apply", "prop-123"}
    end

    test "routes revise synonyms to proposal_revise" do
      session_digest = %{"active_proposal_id" => "prop-456", "active_proposal_status" => "draft"}

      assert MessageClassifier.classify_proposal_command("revise", session_digest) ==
               {:proposal_action, "proposal_revise", "prop-456"}

      assert MessageClassifier.classify_proposal_command("revision", session_digest) ==
               {:proposal_action, "proposal_revise", "prop-456"}

      assert MessageClassifier.classify_proposal_command("rework", session_digest) ==
               {:proposal_action, "proposal_revise", "prop-456"}
    end

    test "routes cancel synonyms to proposal_cancel" do
      session_digest = %{"active_proposal_id" => "prop-789", "active_proposal_status" => "draft"}

      assert MessageClassifier.classify_proposal_command("cancel", session_digest) ==
               {:proposal_action, "proposal_cancel", "prop-789"}

      assert MessageClassifier.classify_proposal_command("discard", session_digest) ==
               {:proposal_action, "proposal_cancel", "prop-789"}

      assert MessageClassifier.classify_proposal_command("reject", session_digest) ==
               {:proposal_action, "proposal_cancel", "prop-789"}

      assert MessageClassifier.classify_proposal_command("abort", session_digest) ==
               {:proposal_action, "proposal_cancel", "prop-789"}
    end

    test "returns :not_a_proposal_command when no active proposal" do
      session_digest = %{}

      assert MessageClassifier.classify_proposal_command("approve", session_digest) ==
               :not_a_proposal_command

      assert MessageClassifier.classify_proposal_command("revise", session_digest) ==
               :not_a_proposal_command
    end

    test "returns :not_a_proposal_command when proposal status is applied" do
      session_digest = %{
        "active_proposal_id" => "prop-123",
        "active_proposal_status" => "applied"
      }

      assert MessageClassifier.classify_proposal_command("approve", session_digest) ==
               :not_a_proposal_command
    end

    test "returns :not_a_proposal_command when proposal status is cancelled" do
      session_digest = %{
        "active_proposal_id" => "prop-123",
        "active_proposal_status" => "cancelled"
      }

      assert MessageClassifier.classify_proposal_command("revise", session_digest) ==
               :not_a_proposal_command
    end

    test "returns :not_a_proposal_command when message doesn't match any action" do
      session_digest = %{"active_proposal_id" => "prop-123", "active_proposal_status" => "draft"}

      assert MessageClassifier.classify_proposal_command("what do you think?", session_digest) ==
               :not_a_proposal_command
    end

    test "is case-insensitive" do
      session_digest = %{"active_proposal_id" => "prop-123", "active_proposal_status" => "draft"}

      assert MessageClassifier.classify_proposal_command("APPROVE", session_digest) ==
               {:proposal_action, "proposal_apply", "prop-123"}

      assert MessageClassifier.classify_proposal_command("Revise", session_digest) ==
               {:proposal_action, "proposal_revise", "prop-123"}
    end

    test "does not treat 'change' as a revise synonym" do
      session_digest = %{"active_proposal_id" => "prop-123", "active_proposal_status" => "draft"}

      assert MessageClassifier.classify_proposal_command("change the proposal", session_digest) ==
               :not_a_proposal_command
    end
  end
end
