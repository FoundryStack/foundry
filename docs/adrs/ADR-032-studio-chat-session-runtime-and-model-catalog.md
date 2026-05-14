# ADR-032: Studio Chat Session Runtime and Model Catalog

**Status:** Accepted
**Date:** 2026-05-14
**Deciders:** Platform team

---

## Context

Foundry Studio's integrated chat workspace had three linked problems:

1. The composer blocked while a reply was streaming, so follow-up prompts could not be staged.
2. Session tabs were not reliably restored after reload because browser workspace persistence and server hydration drifted apart.
3. The model selector was provider-first and hardcoded, which made local model families hard to extend and LM Studio availability misleading.

These issues made the Studio chat feel unlike a modern coding agent workspace and caused users to lose active sessions after a refresh.

---

## Decision

**Adopt a session-aware chat runtime with optimistic queued sends and a model-first catalog.**

### Interaction model

- Sending a message immediately renders the user bubble and clears the composer.
- If no assistant turn is in flight, the message starts streaming immediately.
- If an assistant turn is already in flight, the message is added to a per-session FIFO queue and marked as queued in the transcript.
- When the active turn completes or errors, the next queued message is dispatched automatically.

### Session bootstrap and persistence

- Browser workspace state stores `workspace_id`, `open_session_ids`, and `active_session_id`.
- The LiveView restores from persisted session files when browser state is empty.
- If no sessions exist yet for the current project, Foundry creates a new session automatically.
- Session documents persist the selected model alongside messages and digest metadata.

### Model selection

- The UI selects a model entry, not just a provider family.
- Local families may expose curated entries even when multiple models share the same execution backend.
- LM Studio models are discovered dynamically from `/v1/models`.
- Unsupported families remain visible but disabled so the surface stays honest about what exists versus what is currently runnable.

---

## Consequences

- Studio chat behaves more like Claude Code in VS Code: the composer stays responsive, queued prompts are visible, and session tabs survive reloads.
- Provider dispatch becomes metadata-driven, which reduces future UI churn when model inventories change.
- LM Studio visibility now reflects actual runtime availability instead of stale configuration.
- The session runtime becomes more explicit about queued, sending, and completed user turns.
