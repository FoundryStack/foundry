# Runbook: Claude Code Unavailable

**Alert source:** Chat UI returns placeholder response on message send
**Severity:** Low — chat is non-critical; all Mix tasks and visualization panels remain functional

---

## Symptoms

- Chat UI shows "Claude Code is not installed" message
- Messages send but only receive fallback responses
- No streaming indicator appears

---

## Diagnosis

### Step 1: Verify Claude Code installation

```bash
claude --version
```

Expected output: `X.Y.Z (Claude Code)`

If command not found: Claude Code is not installed.

### Step 2: Verify authentication

```bash
claude auth status
```

Expected: `"loggedIn": true`

If not logged in: run `claude auth login` and follow the browser OAuth flow.

### Step 3: Test headless mode

```bash
claude -p "Say hello" --output-format json
```

Expected: `{"type":"result","result":"hello",...}`

If this fails: check the error output for rate limits, quota issues, or model errors.

---

## Recovery

### Option A: Install Claude Code

```bash
npm install -g @anthropic-ai/claude-code
claude auth login
```

Restart Foundry Studio (`mix foundry.studio` or `mix phx.server`).

### Option B: Use req_llm with API key instead

```bash
# In your environment
export ANTHROPIC_API_KEY="sk-ant-..."
```

Or configure in `config/dev.exs`:

```elixir
config :req_llm, anthropic_api_key: "sk-ant-..."
config :foundry, :llm_provider, :req_llm
```

Restart Foundry Studio.

---

## Verification

After recovery:

```bash
# Start the studio
mix phx.server

# Open http://localhost:4000/foundry/chat
# Send a test message
# Verify streaming response appears
```

---

## Monitoring

The Chat UI self-reports provider status. Check the placeholder message — if it mentions
"API key" instead of "Claude Code", the provider is configured for `req_llm` but no key is set.

All Mix tasks (`mix foundry.context`, `mix foundry.project.status`, etc.) remain functional
regardless of LLM provider status.