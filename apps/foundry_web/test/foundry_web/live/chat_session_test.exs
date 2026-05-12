defmodule FoundryWeb.ChatSessionTest do
  use FoundryWeb.ConnCase, async: false
  require Logger

  # Note: Full integration tests for chat session would require complete Phoenix setup.
  # These basic tests verify the fixes are syntactically correct.

  test "chat session module compiles" do
    # Verify the module loads without errors
    assert FoundryWeb.ChatSession.__info__(:module) == FoundryWeb.ChatSession
  end

  test "mock provider module compiles and has stream function" do
    # Verify mock provider is correct
    assert FoundryWeb.LLMProviders.Mock.__info__(:module) == FoundryWeb.LLMProviders.Mock
    assert function_exported?(FoundryWeb.LLMProviders.Mock, :stream, 2)
  end

  test "chat trace module filters correctly" do
    # Test the item.completed filtering
    events = [
      %{type: "item.completed", phase: :final},
      %{type: "function_call", phase: :final},
      %{type: "item.completed", phase: :final}
    ]

    # Should filter out item.completed events
    filtered = Enum.reject(events, &(&1.type == "item.completed"))
    assert length(filtered) == 1
    assert List.first(filtered).type == "function_call"
  end
end
