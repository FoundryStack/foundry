defmodule Foundry.Chat.MessageClassifier do
  @moduledoc "Classifies chat messages into mode (ask/change) and proposal commands."

  @ask_override_patterns Enum.map(
    ["review", "explain", "audit", "understand", "describe",
     "list", "check if", "show me"],
    fn word ->
      if String.contains?(word, " "),
        do: Regex.compile!("(?i)#{Regex.escape(word)}"),
        else: Regex.compile!("(?i)\\b#{Regex.escape(word)}\\b")
    end
  )

  @change_word_patterns Enum.map(
    ["fix", "implement", "edit", "update", "change", "create",
     "add", "remove", "delete", "rename", "refactor", "migrate",
     "write test", "write tests"],
    fn word ->
      if String.contains?(word, " "),
        do: Regex.compile!("(?i)#{Regex.escape(word)}"),
        else: Regex.compile!("(?i)\\b#{Regex.escape(word)}\\b")
    end
  )

  @proposal_apply_patterns Enum.map(
    ~w[approve apply confirm proceed],
    &Regex.compile!("(?i)\\b#{Regex.escape(&1)}\\b")
  )

  @proposal_revise_patterns Enum.map(
    ~w[revise revision rework],
    &Regex.compile!("(?i)\\b#{Regex.escape(&1)}\\b")
  )

  @proposal_cancel_patterns Enum.map(
    ~w[cancel discard reject abort],
    &Regex.compile!("(?i)\\b#{Regex.escape(&1)}\\b")
  )

  @spec classify_mode(String.t()) :: :ask | :change
  def classify_mode(message) do
    if Enum.any?(@ask_override_patterns, &Regex.match?(&1, message)) do
      :ask
    else
      if Enum.any?(@change_word_patterns, &Regex.match?(&1, message)) do
        :change
      else
        :ask
      end
    end
  end

  @spec classify_proposal_command(String.t(), map()) ::
          {:proposal_action, String.t(), String.t()} | :not_a_proposal_command
  def classify_proposal_command(message, session_digest) do
    proposal_id = Map.get(session_digest, "active_proposal_id")
    proposal_status = Map.get(session_digest, "active_proposal_status")

    cond do
      is_nil(proposal_id) -> :not_a_proposal_command
      proposal_status in ["applied", "cancelled"] -> :not_a_proposal_command
      Enum.any?(@proposal_apply_patterns, &Regex.match?(&1, message)) ->
        {:proposal_action, "proposal_apply", proposal_id}
      Enum.any?(@proposal_revise_patterns, &Regex.match?(&1, message)) ->
        {:proposal_action, "proposal_revise", proposal_id}
      Enum.any?(@proposal_cancel_patterns, &Regex.match?(&1, message)) ->
        {:proposal_action, "proposal_cancel", proposal_id}
      true -> :not_a_proposal_command
    end
  end
end
