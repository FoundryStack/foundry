# ADR-025: Claude Code CLI as Default Dev-Time LLM Provider

**Status:** Accepted
**Date:** 2026-04-12
**Deciders:** Platform team

---

## Context

Foundry's Chat UI (`FoundryWeb.ChatLive`) requires an LLM to respond to user messages.
The existing path uses `req_llm` + `AshAi.ToolLoop` which makes HTTP requests to the
Anthropic API. This requires an `ANTHROPIC_API_KEY` environment variable.

For development, we want a zero-API-key path that uses the developer's existing Claude
Code CLI authentication (browser OAuth). Claude Code is installed on developer machines
and uses Anthropic's API via browser auth — no separate API key management required.

This is the same model used by OpenAI Codex CLI, Google Antigravity, and other agent
tools: the CLI is the inference backend, and the host application provides domain
context via system prompts.

---

## Decision

**Use Claude Code CLI (`claude -p`) as the default LLM provider for Foundry's Chat UI
in development mode.**

`Foundry.ClaudeCodeProvider` spawns Claude Code as a subprocess, passes Foundry's
system prompt and conversation history, and streams the response back via JSON
events.

### Why `claude -p` (headless) and not `claude mcp serve`

| Factor | `claude -p` (chosen) | `claude mcp serve` |
|---|---|---|
| Direction | Foundry calls Claude | Claude calls Foundry |
| Control | Foundry owns agent loop | Claude owns agent loop |
| Tools | Claude's tools (Bash, Read, Grep...) | Claude's tools |
| System prompt | Foundry provides it | Claude provides it |
| Streaming | Native (`stream-json`) | Native |
| Complexity | ~80 lines Port wrapper | Requires MCP client library |
| New deps | Zero | Requires `hermes_mcp` or similar |

`claude -p` keeps Foundry as the orchestrator. Claude Code acts as the reasoning
engine with its own tool set. This matches the architecture of Codex CLI and
Antigravity — they are agents with tools; the host application provides context.

### Architecture

```
Foundry ChatLive
  ├── System Prompt (AGENTS.md, stack versions, project context)
  ├── Conversation History (user + assistant messages)
  └── Port.open({:spawn, "claude -p ..."})
        ├── --system-prompt "<foundry-context>"
        ├── --output-format stream-json
        ├── --verbose
        ├── --include-partial-messages
        └── stdin: conversation as text
              │
              ▼
        Claude Code (subprocess)
          ├── Tools: Bash, Read, Grep, Glob, Edit, Write, WebFetch...
          ├── Model: claude-opus-4-6 (default, browser auth)
          └── stdout: stream-json events
```

### Message format

Conversation history is formatted as text:

```
user: <first message>

assistant: <response>

user: <follow-up>
```

This is passed via stdin. The system prompt is passed via `--system-prompt`.
Streaming output is parsed from `stream-json` events on stdout.

### Configuration

```elixir
# config/dev.exs
config :foundry, :llm_provider, :claude_code
config :foundry, :claude_code,
  timeout_ms: 120_000,
  max_output_tokens: 4096,
  model: nil  # nil = Claude Code default (configurable in Claude settings)
```

### Fallback behaviour

If `claude` is not found on PATH, the Chat UI falls back to a placeholder response
with instructions to install Claude Code or configure an API key for `req_llm`.

### Production path

This does **not** replace `req_llm` for target platforms. Target platforms continue
to use `req_llm` + `AshAi.ToolLoop` with their own API keys. Claude Code is the
dev-time default for Foundry Studio's Chat UI only.

---

## Streaming specification

Claude Code's `--output-format stream-json --verbose --include-partial-messages`
emits newline-delimited JSON events:

```json
{"type":"system","subtype":"init",...}
{"type":"assistant","message":{...},...}
{"type":"result","subtype":"success","result":"...",...}
```

`Foundry.ClaudeCodeProvider` parses each line, extracts text from `assistant` events
for incremental streaming to LiveView, and extracts the final `result` field from the
`result` event for storage.

---

## Consequences

- Foundry Studio Chat UI works in dev with zero API key configuration
- Claude Code uses its own tools (Bash, Read, Grep, etc.) — it can read files and run commands
- System prompt from Foundry provides domain context (AGENTS.md, INV rules, stack versions)
- Streaming responses appear incrementally in the Chat UI
- If Claude Code is not installed, the Chat UI falls back gracefully with setup instructions
- Target platforms continue to use `req_llm` independently