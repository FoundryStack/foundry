# Runbook: Studio UX Degradation

**Applies to:** Foundry Studio UI — rendering, panel loading, WebSocket connectivity  
**Component:** Phoenix LiveView application (`mix foundry.studio`)  
**Last tested:** —  
**Escalation:** Platform team (`#foundry-studio-platform`)

---

## Symptoms

- System map takes >3 seconds to render (performance budget: ADR-012)
- Any panel shows loading state indefinitely (>10 seconds)
- "Unable to connect" or WebSocket disconnect banner visible in the Studio header
- Copilot shows spinner but emits no first token within 5 seconds
- Review panel diff area is blank on a proposal that has a diff
- Node detail drawer opens but shows no content
- Notification badge count is stale or not updating

---

## Step 1: Identify the Failure Layer

Three distinct layers can cause UX degradation. Identify which before taking action.

**Layer 1 — WebSocket / LiveView process**
Signs: Disconnect banner visible. Copilot messages do not send or receive. Panel updates
have frozen mid-session. The "reconnecting…" spinner appears.

**Layer 2 — Mix task subprocess (data retrieval)**
Signs: Studio loaded initially but specific panels time out when navigating to them.
Node detail panel spins on click. Copilot shows "Building context…" without progressing.

**Layer 3 — LLM API (copilot only)**
Signs: All five visualization panels load and update correctly. Only the copilot spinner
is stuck. The system map, compliance matrix, operations board, and test coverage map
are unaffected.

Proceed to the step matching your layer. If unclear, start with Step 2.

---

## Step 2: WebSocket / LiveView Disconnection

```bash
# Verify the Studio process is running
ps aux | grep "foundry.studio"

# If not running (local mode):
# Navigate to the project directory and restart
mix foundry.studio

# Check if the port is accessible
curl -I http://localhost:4001
# Expected: HTTP 200 with upgrade headers available
```

**Intermittent disconnects (<30 seconds, then reconnects automatically):** This is expected
behaviour during a deploy rolling restart in cloud mode, or when the machine suspends.
LiveView reconnects automatically. The disconnect banner clears on reconnect. No action required.

**Persistent disconnect (>2 minutes without reconnect):**

```bash
# Check Studio logs for the disconnect reason
mix foundry.logs --tail=100 --filter=websocket

# Common causes and fixes:

# 1. Idle timeout (LiveView process killed after inactivity)
#    Fix: increase timeout in config/foundry_studio.exs
#    config :phoenix, :live_view, timeout: 86_400_000  # 24h in ms

# 2. Network proxy stripping WebSocket upgrade headers
#    Signs: connects briefly, immediately disconnects
#    Fix: configure proxy to pass Upgrade and Connection headers

# 3. Node restart in cloud mode
#    Signs: disconnect happened at deployment time
#    Fix: libcluster should reform the mesh automatically (check below)
mix foundry.cluster.status
# If node count < expected: check libcluster configuration and cloud platform logs
```

If the process is running but the browser cannot connect: hard-refresh (`Cmd+Shift+R`).
LiveView session state can desync after a deploy. Hard-refresh forces a new session.

---

## Step 3: Slow or Hung Panels (Mix Task Layer)

All panels that show content (all panels except the Copilot) source their data from Mix
task subprocesses. Profile the slow task:

```bash
# Test the primary data source for each panel directly
time mix foundry.diagram.generate --json > /dev/null   # System Map
time mix foundry.compliance.check --json > /dev/null   # Compliance Matrix
time mix foundry.context.all --json > /dev/null        # Operations Board, Test Coverage Map
```

**If any task takes >5 seconds:**

```bash
# The most common cause: project is not compiled or has a large compile delta
mix compile
# After compile: re-run the slow task to check if it recovers

# Second most common cause: the project has raw Ecto modules
# Foundry falls back to a slower module scan for modules it can't introspect via Spark
# Check for direct Ecto.Schema usage:
grep -r "use Ecto.Schema" lib/ | wc -l
# If >0: these modules cause slower introspection — see ADR-001 on raw Ecto limitations
```

**If `mix foundry.context <Module>` specifically times out for one module:**
That module may have a cyclic dependency or a DSL declaration that causes Spark to loop.

```bash
mix foundry.context MyApp.Finance.ProblemModule --timeout=10s 2>&1
# If it exits with timeout: file an issue with the module path
# Workaround: exclude the module temporarily via manifest under `context_exclusions:`
```

**If diagram.generate is fast but the System Map still renders slowly:**
The bottleneck is the D3 rendering pipeline in the browser. Check the browser console
for JavaScript errors. Common causes:

- Browser tab was backgrounded (CPU throttled). Bring tab to foreground and wait for render to complete.
- >200 nodes being rendered — the D3 force simulation takes time. After initial render, interaction should be fast.
- Browser memory pressure — try closing other tabs and reloading.

---

## Step 4: Copilot Spinner Without Response (LLM Layer)

```bash
# Send a minimal diagnostic request to verify API connectivity
mix foundry.copilot.ping
# This sends a <100 token request with no project context
# Expected: response within 3 seconds
# On success: "API reachable. Model: claude-sonnet-[version]. Latency: Xms"
```

**If ping fails:**

```bash
# Check Studio logs for the error code
mix foundry.logs --tail=50 --filter=llm_api

# Error: :authentication_error
# The API key is invalid or expired
mix foundry.config --check=llm_api_key
# Rotate the key in config/foundry_studio.exs and restart Studio

# Error: :rate_limited
# The team is generating many proposals simultaneously
# The engine queues and retries with exponential backoff
# The copilot panel shows: "Waiting for API availability…"
# If persistent (>5 minutes): check Anthropic dashboard for quota usage

# Error: :timeout
# The Anthropic API is slow or unreachable
# Check: https://status.anthropic.com (must be checked by a human — Studio cannot self-diagnose)
# If API is confirmed down: copilot is offline until recovery
# All four visualization panels and all CLI Mix tasks remain functional
```

**If ping succeeds but normal requests hang:**
The context assembly subprocess (`mix foundry.context`) is the bottleneck — see Step 3.
The copilot waits for context before calling the API. A slow Mix task causes apparent
LLM lag even when the API is healthy.

```bash
# Confirm:
time mix foundry.context MyApp.Finance.Wallet
# If >2 seconds: Step 3 is the root cause, not the LLM
```

---

## Step 5: Review Panel Diff Not Rendering

```bash
# Check the proposal's current state
mix foundry.proposals.status --pending

# Expected output includes: proposal_id, state, diff_present: true/false
```

**If `diff_present: false`:** The Igniter dry-run produced no changes — this is a no-op
proposal. The review panel correctly shows "No changes would be made." This is not a bug.
If changes were expected, the operation parameters may be incorrect — dismiss and regenerate.

**If `diff_present: true` but the panel shows blank:**
The LiveView component lost its socket state. Hard-refresh (`Cmd+Shift+R`).
If hard-refresh doesn't restore the diff: dismiss and regenerate. The proposal diff is
stored in `.foundry/proposals/prop_<id>.json` (git-backed) — regeneration is not data
loss, it is re-computation. Foundry has no database (ADR-015).

**If the diff renders but is visually broken (overlapping lines, missing syntax highlighting):**
Browser compatibility issue. Supported browsers: latest Chrome, Firefox, Safari (desktop only).
Mobile browsers are not supported (ADR-012 §Responsive and Mobile).

---

## Step 6: Notification Badge Stale or Not Updating

Notification counts are pushed via Phoenix PubSub over the LiveView WebSocket. A stale count
indicates the WebSocket connection has gone stale without triggering the disconnect banner.

```bash
# Force reconnect: close and reopen the browser tab
# or:
# Hard-refresh: Cmd+Shift+R
```

If the badge remains stale after reconnect:

```bash
# Check PubSub is functioning in cloud mode
mix foundry.cluster.pubsub.check
# Verifies all nodes can publish and receive on the foundry:notifications topic

# In local mode: PubSub is in-process and should always work
# A stale badge in local mode after hard-refresh is a bug — file an issue
```

---

## What Is Never Acceptable

- Clearing the Nebulex cache manually without restarting Studio (cache state may be inconsistent mid-session)
- Modifying `.foundry/proposals/prop_<id>.json` files directly to change state — use
  `mix foundry.proposals.*` commands only; Foundry has no database (ADR-015)
- Disabling the blob hash check to force-apply a stale proposal
- Restarting the Studio process while proposals are PENDING_REVIEW without confirming
  with approvers first (ETS cache is lost on restart; git-backed proposal files are not)

---

## Escalation

If none of the above resolves the issue:

```bash
# Export a full diagnostic bundle
mix foundry.diagnostics --full > /tmp/foundry-diag-$(date +%Y%m%d-%H%M%S).txt
```

The diagnostic bundle includes: Studio process state, recent log tail, Mix task timings,
cluster node status, cache hit/miss rates, and the last 5 error codes from the telemetry
pipeline. It does **not** include LLM prompt content or proposal diffs (to avoid
capturing sensitive domain information).

Post the bundle in `#foundry-studio-platform`. Do not share in public channels.

---

## Related Runbooks

| Symptom | Runbook |
|---|---|
| Copilot context build fails | `docs/runbooks/studio_ux_degradation.md` Step 3 (this file) |
| Scaffold operation fails in review panel | `docs/runbooks/studio_copilot_failure.md` §Scaffold Operation Failure |
| Copilot returns `:llm_api_error` persistently | `docs/runbooks/studio_copilot_failure.md` |
| Approval queue blocked / SLA exceeded | `docs/runbooks/approval_queue_blocked.md` |
| Compliance test failing in CI | `docs/runbooks/compliance_test_failure.md` |