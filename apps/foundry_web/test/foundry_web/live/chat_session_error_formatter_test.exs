defmodule FoundryWeb.ChatSessionErrorFormatterTest do
  use ExUnit.Case, async: true

  alias FoundryWeb.ChatSessionErrorFormatter, as: Formatter

  # ---------------------------------------------------------------------------
  # format_request_error/1
  # ---------------------------------------------------------------------------

  describe "format_request_error/1" do
    test "context_cache_build_failed" do
      msg = Formatter.format_request_error({:context_cache_build_failed, :enoent})
      assert String.contains?(msg, "context cache")
    end

    test "context_build_failed" do
      msg = Formatter.format_request_error({:context_build_failed, :timeout})
      assert String.contains?(msg, "retrieval context")
    end

    test "unknown_provider" do
      msg = Formatter.format_request_error({:unknown_provider, :foobar})
      assert String.contains?(msg, "foobar")
    end

    test "codex_exit" do
      msg = Formatter.format_request_error({:codex_exit, 1, "some output"})
      assert String.contains?(msg, "Claude Code exited")
    end

    test "claude_exit with sandbox output" do
      output = "SecurityException: sandbox violation"
      msg = Formatter.format_request_error({:claude_exit, 1, output})
      assert String.contains?(msg, "sandbox")
    end

    test "claude_exit with governance output" do
      output = "Request blocked by governance policy restriction"
      msg = Formatter.format_request_error({:claude_exit, 1, output})
      assert String.contains?(msg, "governance")
    end

    test "claude_exit with tool restriction output" do
      output = "tool not allowed: bash"
      msg = Formatter.format_request_error({:claude_exit, 1, output})
      assert String.contains?(msg, "tool restrictions")
    end

    test "claude_exit with generic output" do
      output = "some random error happened"
      msg = Formatter.format_request_error({:claude_exit, 1, output})
      assert String.contains?(msg, "Claude Code exited")
    end

    test "lm_studio_error" do
      msg = Formatter.format_request_error({:lm_studio_error, :econnrefused})
      assert String.contains?(msg, "LM Studio")
    end

    test "codex_error with reason" do
      msg = Formatter.format_request_error({:codex_error, :spawn_failed})
      assert String.contains?(msg, "Claude Code error")
    end

    test "claude_error with reason" do
      msg = Formatter.format_request_error({:claude_error, :api_limit})
      assert String.contains?(msg, "Claude error")
    end

    test "parse_error" do
      msg = Formatter.format_request_error({:parse_error, "unexpected token"})
      assert String.contains?(msg, "parse")
    end

    test ":timeout" do
      msg = Formatter.format_request_error(:timeout)
      assert String.contains?(msg, "timed out")
    end

    test "unknown tuple falls through to generic" do
      msg = Formatter.format_request_error({:some_unknown_error, 42})
      assert String.contains?(msg, "Error:")
    end
  end

  # ---------------------------------------------------------------------------
  # format_task_shutdown_error/1
  # ---------------------------------------------------------------------------

  describe "format_task_shutdown_error/1" do
    test "includes reason in output" do
      msg = Formatter.format_task_shutdown_error(:killed)
      assert String.contains?(msg, "interrupted")
    end
  end

  # ---------------------------------------------------------------------------
  # persistence_error/2
  # ---------------------------------------------------------------------------

  describe "persistence_error/2" do
    test "formats with prefix and session_store_down" do
      msg = Formatter.persistence_error("Failed to save", :session_store_down)
      assert String.contains?(msg, "Failed to save")
      assert String.contains?(msg, "unavailable")
    end

    test "formats with prefix and Ash.Error.Invalid" do
      msg = Formatter.persistence_error("Save error", %Ash.Error.Invalid{errors: []})
      assert String.contains?(msg, "Invalid session")
    end

    test "formats with prefix and atom reason" do
      msg = Formatter.persistence_error("Prefix", :enoent)
      assert String.contains?(msg, "Prefix")
      assert String.contains?(msg, "enoent")
    end

    test "formats with prefix and unknown reason" do
      msg = Formatter.persistence_error("Prefix", %{some: :map})
      assert String.contains?(msg, "Prefix")
    end
  end
end
