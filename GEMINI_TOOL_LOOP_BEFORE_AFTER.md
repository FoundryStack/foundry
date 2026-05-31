# Gemini Tool Loop Fix: Before vs After

## The Critical Bug

Gemini's API returns a unique `id` with every `functionCall`. This id **must be returned unchanged** in the corresponding `functionResponse`. Without it, the model cannot correlate results to requests.

## Before Fix

### ❌ Code: Ignoring the ID field
```elixir
# Line 112 - OLD: Only destructuring name and args
Enum.map(tool_calls, fn %{"name" => name, "args" => args} ->
  # ... execute tool ...
  
  # Line 150-155 - OLD: functionResponse WITHOUT id
  %{
    "functionResponse" => %{
      "name" => name,
      "response" => result
    }
  }
end)
```

### ❌ Result: API Contract Violation
```
Gemini sends:
{
  "functionCall": {
    "name": "list_directory",
    "args": {"path": "/lib"},
    "id": "call_abc123xyz"  ← Gemini provides this
  }
}

We send back:
{
  "functionResponse": {
    "name": "list_directory",
    "response": {...},
    "id": ???  ← MISSING! ❌
  }
}

Result: Gemini cannot correlate results → repeats tool calls infinitely
```

### ❌ Observed Behavior
```
iteration=0: tool_calls=[list_directory]
iteration=1: tool_calls=[list_directory]  ← Same call repeated!
iteration=2: tool_calls=[list_directory]  ← Still repeating!
iteration=3: tool_calls=[list_directory]  ← ...
...
iteration=15: Error: {:max_iterations_exceeded, 15}
```

---

## After Fix

### ✅ Code: Preserving the ID field
```elixir
# Line 112-115 - NEW: Extract name, args, AND id
Enum.map(tool_calls, fn tool_call ->
  name = tool_call["name"]
  args = tool_call["args"]
  id = tool_call["id"]  # ← CAPTURED! ✅
  
  # ... execute tool ...
  
  # Line 154-160 - NEW: functionResponse WITH id
  %{
    "functionResponse" => %{
      "name" => name,
      "response" => result,
      "id" => id  # ← RETURNED! ✅
    }
  }
end)
```

### ✅ Result: Proper API Contract
```
Gemini sends:
{
  "functionCall": {
    "name": "list_directory",
    "args": {"path": "/lib"},
    "id": "call_abc123xyz"
  }
}

We send back:
{
  "functionResponse": {
    "name": "list_directory",
    "response": {...},
    "id": "call_abc123xyz"  ← MATCHES! ✅
  }
}

Result: Gemini correlates results correctly → moves to final answer
```

### ✅ Expected Behavior
```
iteration=0: tool_calls=[list_directory]
Tool executes → result sent with matching id → Gemini processes result

iteration=1: Gemini response has no new tool_calls
Final answer provided ✅

Total iterations: 1 (instead of 15)
```

---

## Debug Logging Improvement

### ❌ Before
```
Tool call: list_directory with args: ...
Tool result: list_directory succeeded
Gemini response: has_tool_calls=true, tool_calls=1, text_length=0, iteration=0
```

### ✅ After
```
Tool call: list_directory (id=call_abc123xyz) with args: ...
Tool result: list_directory (id=call_abc123xyz) succeeded
Gemini response: iteration=0, tool_calls=[list_directory], text_length=123
```

ID is now visible in logs, making debugging much easier.

---

## Test Coverage

### ✅ 6 New Tests (All Passing)

1. **functionResponse includes id field** ✓
   - Verifies id is extracted and preserved

2. **Multiple tool calls preserve unique ids** ✓
   - Confirms each tool's id is maintained separately

3. **Response matches Gemini API spec** ✓
   - Validates structure compliance

4. **Message format for Gemini API** ✓
   - Ensures the full message structure is correct

5. **Max iterations limit** ✓
   - Confirms loop termination works

6. **Trace events include id** ✓
   - Verifies debugging visibility

**All 6 tests passing in CI/CD** ✅

---

## Impact Summary

| Aspect | Before Fix | After Fix |
|--------|-----------|-----------|
| **API Contract Compliance** | ❌ Broken | ✅ Compliant |
| **Tool Loop Iterations** | 10-15 | 1-2 |
| **Repeated Tool Calls** | Yes | No |
| **ID Field Preserved** | ❌ Dropped | ✅ Maintained |
| **Model Correlation** | Broken | Working |
| **Test Coverage** | None | 6 tests |
| **Debug Logging** | No IDs | ID included |

---

## Files Changed

```
apps/foundry/lib/foundry/chat/tool_loop.ex
  - Modified execute_tool_calls/5
  - Extract id field from tool_call map
  - Include id in functionResponse
  - Add id to trace events and logging
  
apps/foundry/test/foundry/chat/tool_loop_test.exs
  - 6 new comprehensive tests
  - Verify API spec compliance
  - Test id preservation
  - Validate message structure
```

---

## Verification

To verify the fix is working:

```bash
# Run tests
mix test apps/foundry/test/foundry/chat/tool_loop_test.exs
# Expected: 6 tests, 0 failures ✅

# Check logs during tool execution
tail -f /tmp/server.log | grep "Tool call.*id="
# Expected: Tool call: list_directory (id=call_abc123xyz)

# Check iteration count in trace panel
# Before: 10-15 iterations to complete
# After: 1-2 iterations to complete
```

---

## References

- [Gemini API: Function Calling](https://ai.google.dev/gemini-api/docs/function-calling)
- [Gemini API: Tools](https://ai.google.dev/gemini-api/docs/tools)
- Commit: `00ec395e`
