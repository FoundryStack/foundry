defmodule FoundryWeb.ChatSessionErrorFormatter do
  @moduledoc """
  Error message formatting for chat requests.

  Converts internal error tuples to user-facing messages, detecting specific
  failure modes (sandbox violations, governance restrictions, tool blockers) and
  providing targeted guidance.
  """

  alias FoundryWeb.ChatConfig

  @doc """
  Formats a request error tuple into a user-facing message.
  """
  def format_request_error({:context_cache_build_failed, _reason}) do
    "Failed to build context cache. Check project root and filesystem permissions."
  end

  def format_request_error({:context_build_failed, _reason}) do
    "Failed to build retrieval context. Check connectivity and project configuration."
  end

  def format_request_error({:unknown_provider, provider}) do
    "Unknown LLM provider: #{provider}"
  end

  def format_request_error({:codex_exit, _code, output}) do
    "Claude Code exited with error:\n\n#{summarize_output(output)}"
  end

  def format_request_error({:claude_exit, _code, output}) do
    error_output = summarize_output(output)

    cond do
      sandbox_restriction?(error_output) ->
        "Claude Code request blocked due to sandbox restrictions."

      governance_restriction?(error_output) ->
        "Request blocked by governance policy. This may indicate a security concern."

      provider_tool_restriction?(error_output) ->
        "Claude Code request blocked due to tool restrictions."

      true ->
        "Claude Code exited with error:\n\n#{error_output}"
    end
  end

  def format_request_error({:lm_studio_error, _reason}) do
    "LM Studio connection failed. Ensure LM Studio is running and accessible."
  end

  def format_request_error({:codex_error, reason}),
    do: "Claude Code error: #{inspect(reason)}"

  def format_request_error({:claude_error, reason}),
    do: "Claude error: #{inspect(reason)}"

  def format_request_error({:parse_error, reason}) do
    "Failed to parse LLM response: #{inspect(reason)}"
  end

  def format_request_error(:timeout) do
    "Request timed out. Try again or adjust your query."
  end

  def format_request_error(reason),
    do: "Error: #{inspect(reason)}"

  @doc """
  Formats a task shutdown error.
  """
  def format_task_shutdown_error(reason),
    do: "Task interrupted: #{inspect(reason)}"

  @doc """
  Formats a persistence error with context.
  """
  def persistence_error(prefix, reason) do
    "#{prefix}: #{persistence_reason(reason)}"
  end

  # Private helpers

  defp persistence_reason(:session_store_down),
    do: "Session store unavailable"

  defp persistence_reason(%Ash.Error.Invalid{}),
    do: "Invalid session data"

  defp persistence_reason(reason) when is_atom(reason),
    do: Atom.to_string(reason)

  defp persistence_reason(_reason),
    do: "Unknown error"

  defp sandbox_restriction?(output) when is_binary(output) do
    String.contains?(output, ["sandbox", "SecurityException", "permission denied"])
  end

  defp governance_restriction?(output) when is_binary(output) do
    String.contains?(output, ["governance", "policy", "restricted"])
  end

  defp provider_tool_restriction?(output) when is_binary(output) do
    String.contains?(output, ["tool not allowed", "tool_name_mismatch"])
  end

  defp summarize_output(output) when is_binary(output) do
    if ChatConfig.show_debug_details?() do
      output
    else
      output
      |> String.split("\n")
      |> Enum.take(5)
      |> Enum.join("\n")
    end
  end
end
