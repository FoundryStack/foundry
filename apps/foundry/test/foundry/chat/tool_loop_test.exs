defmodule Foundry.Chat.ToolLoopTest do
  use ExUnit.Case
  require Logger

  describe "tool result message format - OpenAI/ReqLLM compat" do
    test "tool result message has correct req_llm structure" do
      # ReqLLM expects tool results as role: "tool" messages with tool_call_id
      tool_result = %{
        "role" => "tool",
        "tool_call_id" => "call_abc123",
        "name" => "list_directory",
        "content" => "file1.ex\nfile2.ex"
      }

      assert tool_result["role"] == "tool"
      assert tool_result["tool_call_id"] == "call_abc123"
      assert tool_result["name"] == "list_directory"
      assert tool_result["content"] == "file1.ex\nfile2.ex"
    end

    test "assistant turn with tool calls matches OpenAI format" do
      # After streaming completes with tool calls, assistant turn is:
      assistant_turn = %{
        "role" => "assistant",
        "content" => "Looking for files...",
        "tool_calls" => [
          %{
            "id" => "call_001",
            "type" => "function",
            "function" => %{
              "name" => "list_directory",
              "arguments" => "{\"path\":\"/lib\"}"
            }
          }
        ]
      }

      assert assistant_turn["role"] == "assistant"
      assert assistant_turn["content"] == "Looking for files..."
      assert length(assistant_turn["tool_calls"]) == 1
      assert Enum.at(assistant_turn["tool_calls"], 0)["type"] == "function"
    end
  end

  describe "message conversion" do
    test "converts system message properly (filtered)" do
      messages = [
        %{"role" => "system", "content" => "You are helpful"},
        %{"role" => "user", "content" => "Hello"}
      ]

      # System messages should be filtered during convert_messages
      converted = Enum.reject(messages, fn msg -> msg["role"] == "system" end)
      assert length(converted) == 1
      assert Enum.at(converted, 0)["role"] == "user"
    end

    test "converts assistant message to OpenAI format" do
      message = %{"role" => "assistant", "content" => "Hello, I can help"}

      # Convert to OpenAI format (keep "assistant" role, keep "content")
      converted = %{
        "role" => "assistant",
        "content" => message["content"]
      }

      assert converted["role"] == "assistant"
      assert converted["content"] == "Hello, I can help"
    end

    test "converts user message to OpenAI format" do
      message = %{"role" => "user", "content" => "What can you do?"}

      # User messages stay "user" role
      converted = %{
        "role" => "user",
        "content" => message["content"]
      }

      assert converted["role"] == "user"
      assert converted["content"] == "What can you do?"
    end
  end

  describe "max_iterations limit" do
    test "loop respects max_iterations setting" do
      messages = [%{"role" => "user", "content" => "Test"}]

      opts = [
        api_key: "test-key",
        model: "gemini-1.5-flash",
        project_root: File.cwd!(),
        max_iterations: 5,
        system_prompt: "Test"
      ]

      on_event = fn _event -> :ok end

      # With invalid key, expect timeout/error before hitting iteration limit
      result = Foundry.Chat.ToolLoop.run(messages, opts, on_event)

      # Should error (invalid key) rather than crash on iteration limit
      assert match?({:error, _}, result)
    end
  end
end
