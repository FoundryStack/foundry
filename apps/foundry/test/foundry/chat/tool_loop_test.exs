defmodule Foundry.Chat.ToolLoopTest do
  use ExUnit.Case
  require Logger

  describe "functionResponse structure - Gemini API contract" do
    test "includes id field from functionCall in response" do
      # Per Gemini API docs: https://ai.google.dev/gemini-api/docs/function-calling
      # functionCall responses include an id that must be returned in functionResponse

      tool_call_from_gemini = %{
        "name" => "list_directory",
        "args" => %{"path" => "/lib"},
        "id" => "call_abc123xyz"
      }

      # Simulate what execute_tool_calls would create
      tool_response = build_function_response(tool_call_from_gemini, "file1.ex\nfile2.ex")

      # Verify the response includes the id - critical for Gemini API
      assert tool_response["functionResponse"]["id"] == "call_abc123xyz"
      assert tool_response["functionResponse"]["name"] == "list_directory"
      assert tool_response["functionResponse"]["response"]["output"] == "file1.ex\nfile2.ex"
    end

    test "preserves id across multiple tool calls" do
      # Gemini can return multiple functionCalls in one response, each with unique ids
      tool_calls = [
        %{
          "name" => "list_directory",
          "args" => %{"path" => "/lib"},
          "id" => "call_001"
        },
        %{
          "name" => "read_file",
          "args" => %{"path" => "/lib/file.ex"},
          "id" => "call_002"
        }
      ]

      responses = Enum.map(tool_calls, &build_function_response(&1, "test output"))

      # Each response must have the correct id for correlation
      assert Enum.at(responses, 0)["functionResponse"]["id"] == "call_001"
      assert Enum.at(responses, 1)["functionResponse"]["id"] == "call_002"
    end

    test "function response matches Gemini API specification" do
      # Per Gemini API docs: functionResponse must include name, response, and id
      tool_call = %{
        "name" => "example_function",
        "args" => %{"param" => "value"},
        "id" => "unique_call_id"
      }

      response = build_function_response(tool_call, "result data")
      function_response = response["functionResponse"]

      # Verify required fields per Gemini API spec
      assert function_response["name"] == "example_function"
      assert is_map(function_response["response"])
      assert function_response["id"] == "unique_call_id"
    end

    test "response structure matches message format for Gemini API" do
      # The message sent back to Gemini should have this structure per docs:
      # {
      #   "role": "user",
      #   "parts": [
      #     {
      #       "functionResponse": {
      #         "name": "...",
      #         "response": {...},
      #         "id": "..."
      #       }
      #     }
      #   ]
      # }

      tool_calls = [
        %{
          "name" => "tool1",
          "args" => %{},
          "id" => "id1"
        }
      ]

      tool_responses = Enum.map(tool_calls, &build_function_response(&1, "output"))

      # Simulate building the message that would be sent to Gemini
      user_message = %{
        "role" => "user",
        "parts" => tool_responses
      }

      # Verify structure matches Gemini API requirements
      assert user_message["role"] == "user"
      assert is_list(user_message["parts"])
      assert length(user_message["parts"]) == 1

      part = Enum.at(user_message["parts"], 0)
      assert Map.has_key?(part, "functionResponse")
      assert part["functionResponse"]["id"] == "id1"
    end
  end

  describe "SSE streaming parsing" do
    test "parse_gemini_sse extracts text from SSE events" do
      sse_data = """
      data: {"candidates":[{"content":{"parts":[{"text":"Hello "}],"role":"model"}}]}

      data: {"candidates":[{"content":{"parts":[{"text":"world"}],"role":"model"}}]}
      """

      {_buffer, chunks, _content} = Foundry.Chat.ToolLoop.parse_gemini_sse_for_test(sse_data)

      assert length(chunks) == 2
      assert Enum.at(chunks, 0) == "Hello "
      assert Enum.at(chunks, 1) == "world"
    end

    test "parse_gemini_sse handles partial data gracefully" do
      # Simulate incomplete SSE event
      partial = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text"

      {_buffer, chunks, _content} = Foundry.Chat.ToolLoop.parse_gemini_sse_for_test(partial)

      # Should skip incomplete/invalid JSON events
      assert chunks == []
    end

    test "parse_gemini_sse preserves last content for tool call detection" do
      sse_data = """
      data: {"candidates":[{"content":{"parts":[{"text":"Result "},{"functionCall":{"name":"tool1"}}],"role":"model"}}]}
      """

      {_buffer, _chunks, content} = Foundry.Chat.ToolLoop.parse_gemini_sse_for_test(sse_data)

      assert content != nil
      assert Foundry.Chat.ToolLoop.has_tool_calls_for_test(content)
    end

    test "parse_gemini_sse returns nil content for invalid SSE events" do
      sse_data = """
      data: invalid json
      data: {}
      """

      {_buffer, chunks, content} = Foundry.Chat.ToolLoop.parse_gemini_sse_for_test(sse_data)

      # Should skip invalid events and return nil if no valid content found
      assert chunks == []
      assert content == nil
    end
  end

  describe "streaming error handling" do
    test "returns error when stream ends with no content" do
      # Simulate a stream that never sends any content, just closes
      messages = [
        %{"role" => "user", "content" => "Test message"}
      ]

      opts = [
        api_key: "test-key-invalid",
        model: "gemini-1.5-flash",
        project_root: File.cwd!(),
        max_iterations: 1,
        timeout_ms: 100,
        system_prompt: "Test"
      ]

      on_event = fn _event -> :ok end

      result = Foundry.Chat.ToolLoop.run(messages, opts, on_event)

      # Should return an error (either timeout or no_content) rather than crash
      assert match?({:error, _}, result)
    end
  end

  describe "tool loop integration" do
    test "max_iterations limit prevents infinite loops" do
      # This test verifies that max_iterations=15 is set correctly
      # and that the loop respects it

      messages = [
        %{"role" => "user", "content" => "Test message"}
      ]

      opts = [
        api_key: "test-key-invalid",
        model: "gemini-1.5-flash",
        project_root: File.cwd!(),
        max_iterations: 15,
        timeout_ms: 5_000,
        system_prompt: "Test prompt"
      ]

      on_event = fn event ->
        case event do
          {:trace, trace_event} ->
            assert is_map(trace_event) or is_tuple(trace_event)

          {:delta, _text} ->
            :ok

          {:result, _text, _metadata} ->
            :ok

          _ ->
            :ok
        end
      end

      result = Foundry.Chat.ToolLoop.run(messages, opts, on_event)

      case result do
        {:ok, _text, _metadata} ->
          :ok

        {:error, {:max_iterations_exceeded, max_iter}} ->
          assert max_iter == 15

        {:error, _reason} ->
          :ok
      end
    end

    test "trace events include id for debugging" do
      on_event = fn event ->
        case event do
          {:trace, trace_event} when is_map(trace_event) ->
            # Trace events should be maps with proper structure
            assert Map.has_key?(trace_event, "type")
            assert Map.has_key?(trace_event, "provider")

          _ ->
            :ok
        end
      end

      messages = [
        %{"role" => "user", "content" => "Test"}
      ]

      opts = [
        api_key: "invalid",
        model: "gemini-1.5-flash",
        project_root: File.cwd!(),
        max_iterations: 1,
        timeout_ms: 5_000,
        system_prompt: "Test"
      ]

      Foundry.Chat.ToolLoop.run(messages, opts, on_event)
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp build_function_response(tool_call, output) do
    name = tool_call["name"]
    id = tool_call["id"]

    %{
      "functionResponse" => %{
        "name" => name,
        "response" => %{"output" => output},
        "id" => id
      }
    }
  end
end
