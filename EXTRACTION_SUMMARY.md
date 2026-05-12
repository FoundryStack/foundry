# Phoenix LLM Chat Package Extraction Summary

## Overview

Successfully extracted ChatSession into a reusable, open-source library at `/packages/phoenix_llm_chat`. The library is 100% generic with zero Foundry dependencies, while Foundry-specific logic is encapsulated in `FoundryWeb.ChatSessionDomainLogic`.

## Package Structure

### `/packages/phoenix_llm_chat/`

The new library (~1100 lines of generic code) contains:

1. **`phoenix_llm_chat.ex`** — Main public API
   - `mount/2`, `handle_event/3`, `handle_info/2`, `terminate/2`
   - Workspace operations (create, open, switch, delete, rename sessions)

2. **`StreamRuntime`** (~70 lines) — Async task management
   - Streaming event handlers (:delta, :done, :error, :trace)
   - Process lifecycle management (DOWN handlers)
   - Task ref correlation

3. **`Workspace`** (~140 lines) — Multi-tab session management
   - Session creation and switching
   - File-backed session storage abstraction
   - Workspace state broadcasting

4. **`LLMContext`** (~130 lines) — Provider abstraction
   - Provider dispatch (Claude, Codex, LM Studio, HTTP)
   - System prompt building with hooks
   - Provider config and diagnostics

5. **`Core`** (~100 lines) — Event dispatcher
   - Message input/send flow
   - Response finalization
   - Request ref management

6. **`Utilities`** (~60 lines) — Response filtering
   - Error formatting
   - Response normalization
   - Message filtering

7. **`Behaviours.SessionStore`** — Storage backend interface
   - `load/1`, `save/2`, `list/0`, `delete/1` callbacks
   - Allows custom storage implementations

### `/apps/foundry_web/lib/foundry_web/live/chat_session_domain_logic.ex`

Foundry-specific domain logic (~150 lines) containing:

1. **Proposal Management** — Change workflow (apply, revise, cancel)
2. **Activity Run Tracking** — Create, complete, fail runs with trace events
3. **Session Memory Integration** — SpecKit persistence
4. **Foundry Retrieval Context** — Tool results, context cache, retrieval modes
5. **Project-Specific Prompts** — Build system prompt with Foundry headers
6. **UI Rendering Helpers** — Format proposals and activity runs

## Integration Points

### Hook System (Configuration-Driven)

The library uses a hook system for customization:

```elixir
config :phoenix_llm_chat,
  default_provider: "claude",
  session_store: MyApp.FileSessionStore,
  hooks: %{
    :call_llm_stream => &MyApp.LLM.stream/4,
    :build_system_prompt => &MyApp.LLM.system_prompt/2,
    :persist_session => &MyApp.Storage.persist/2,
    :load_session => &MyApp.Storage.load/1,
    :get_provider => &MyApp.LLM.get_provider/1,
    :get_provider_config => &MyApp.LLM.get_provider_config/1
  }
```

### Migration Path

For Foundry integration:

1. Add `:phoenix_llm_chat` to foundry_web dependencies (✅ done)
2. Configure hooks pointing to Foundry.ClaudeCodeProvider, etc.
3. Refactor ChatSession to use PhoenixLLMChat.mount/handle_event/handle_info
4. Use FoundryWeb.ChatSessionDomainLogic for Foundry-specific events
5. Keep existing ChatSession public interface unchanged (no breaking changes)

## What Changed

### New Files
- `/packages/phoenix_llm_chat/` (library, 9 files)
- `/apps/foundry_web/lib/foundry_web/live/chat_session_domain_logic.ex` (domain logic)

### Modified Files
- `/apps/foundry_web/mix.exs` — Added `{:phoenix_llm_chat, path: "../../packages/phoenix_llm_chat"}`

### Deleted Files
- None (existing ChatSession.ex remains intact for now)

## Testing

### Current Status
- ✅ Compilation succeeds with zero errors
- ✅ Dependencies resolved (Phoenix ~> 1.8, Phoenix.LiveView ~> 1.0, Req ~> 0.5)
- ⏳ Integration tests pending (requires SystemMapLive refactor)

### Next Steps

1. **Verify zero API breakage** — SystemMapLive and other consumers call ChatSession unchanged
2. **Implement hook handlers** in Foundry (LLM providers, storage, persistence)
3. **Refactor ChatSession** to orchestrate library + domain logic
4. **Update tests** to verify round-trip chat flow works
5. **Publish library** (optional) to Hex for open source reuse

## Design Decisions

### Why Extract Now (Before Namespace Split)?

✅ **Correct Timing:**
- Clean separation during refactoring
- Library code guaranteed zero Foundry dependencies
- Domain logic stays in Foundry namespace
- Open source ready immediately

### Why Hook System Over Callbacks?

✅ **Configuration-Driven:**
- No compile-time coupling
- Hooks can be swapped at runtime
- Supports multiple provider implementations
- Easy to test with mocks

### Why SessionStore Behaviour?

✅ **Abstraction:**
- File, database, or memory backends
- Users implement once per domain
- Library has no persistence knowledge
- Extensible without library changes

## Benefits

**For Open Source Users:**
- Drop-in streaming chat with multi-tab sessions
- Works with any LLM provider (Claude, Codex, etc.)
- File-backed or custom storage
- Extensible via hooks and behaviours
- Zero Foundry/proprietary dependencies

**For Foundry:**
- Library code never changes for domain features
- Clear responsibility separation
- Easier to maintain and test in isolation
- Can gather feedback from open source users
- Reference implementation shows how to extend

## Compilation

```
==> phoenix_llm_chat
Generated phoenix_llm_chat app

==> foundry_web
Generated foundry_web app
```

All modules compile cleanly with no errors or warnings.
