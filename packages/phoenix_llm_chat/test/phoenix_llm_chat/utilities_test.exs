defmodule PhoenixLLMChat.UtilitiesTest do
  use ExUnit.Case

  test "normalize_usage with valid input returns map with atoms" do
    usage = PhoenixLLMChat.Utilities.normalize_usage(%{
      "input_tokens" => 10,
      "output_tokens" => 20
    })

    assert usage[:input_tokens] == 10
    assert usage[:output_tokens] == 20
    assert usage[:total_tokens] == 30
  end

  test "normalize_usage with partial input" do
    usage = PhoenixLLMChat.Utilities.normalize_usage(%{
      "input_tokens" => 15
    })

    assert usage[:input_tokens] == 15
    assert usage[:output_tokens] == 0
  end

  test "normalize_usage with nil" do
    usage = PhoenixLLMChat.Utilities.normalize_usage(nil)

    assert usage == nil
  end

  test "format_error with binary string" do
    error = PhoenixLLMChat.Utilities.format_error("Connection failed")

    assert error == "Connection failed"
  end

  test "format_error with error tuple" do
    error = PhoenixLLMChat.Utilities.format_error({:error, :timeout})

    assert is_binary(error)
  end

  test "format_error with error map" do
    error = PhoenixLLMChat.Utilities.format_error(%{"error" => "Not found"})

    assert error == "Not found"
  end

  test "format_error with atom" do
    error = PhoenixLLMChat.Utilities.format_error(:timeout)

    assert is_binary(error)
  end

  test "apply_message_filters with no filters returns original response" do
    response = "test response"
    filtered = PhoenixLLMChat.Utilities.apply_message_filters(response, [])

    assert filtered == response
  end

  test "apply_message_filters with custom filter" do
    response = "test response"
    filters = [fn msg -> String.upcase(msg) end]
    filtered = PhoenixLLMChat.Utilities.apply_message_filters(response, filters)

    assert filtered == "TEST RESPONSE"
  end

  test "filter_response with truncate" do
    long_response = String.duplicate("x", 3000)
    result = PhoenixLLMChat.Utilities.filter_response(long_response, :truncate, max_length: 100)

    assert String.length(result) <= 101
  end

  test "filter_response with strip_markdown" do
    markdown = "**bold** text *italic* and `code`"
    result = PhoenixLLMChat.Utilities.filter_response(markdown, :strip_markdown)

    assert String.contains?(result, "bold")
    assert not String.contains?(result, "**")
  end

  test "summarize_response truncates long text" do
    long_text = String.duplicate("abc", 50)
    result = PhoenixLLMChat.Utilities.summarize_response(long_text)

    assert String.contains?(result, "...")
  end
end
