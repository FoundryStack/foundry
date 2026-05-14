# ADR-030: Standalone Distribution and Desktop Shell

**Status:** Accepted
**Date:** 2026-05-13
**Deciders:** Platform team
**Extends:** ADR-004, ADR-006, ADR-021

---

## Context

Foundry currently runs well for contributors as an umbrella application, but it has no
stable end-user distribution path. We need a portable local distribution model that:

1. Preserves Foundry's existing Phoenix/Ash runtime instead of rewriting the backend.
2. Supports macOS and Linux first.
3. Gives us a standalone binary path before we invest in a desktop wrapper.
4. Respects ADR-006 by keeping GitHub Actions workflow changes in proposal form.

The original plan also considered a local SQLite prompt cache. We are explicitly **not**
adopting that at this stage. Current usage is low-concurrency and the extra storage and
cache invalidation complexity is not justified yet.

## Decision

**Adopt a phased distribution model: Burrito-backed standalone runtime first, then a
thin Tauri shell that treats the Foundry runtime as a sidecar.**

### Phase 1: standalone runtime

- Add a stable local launcher contract via `mix foundry.studio`
- Support `--project`, `--port auto|NNNN`, and `--no-browser`
- Resolve an open localhost port, persist it to `~/.foundry.port`, and expose `/healthz`
- Configure an umbrella release that can be wrapped by Burrito for distribution
- Keep the contributor workflow unchanged (`mix phx.server`, umbrella dev tools, etc.)

### Phase 2: desktop shell

- Scaffold a Tauri v2 app in `desktop/foundry-desktop`
- Keep the shell thin: it launches Foundry and points a window at the local HTTP server
- Use Tauri's shell sidecar support to bundle the Burrito-produced Foundry binary and
  start it with the stable `studio --port auto --no-browser` contract
- Prepare sidecar-oriented structure and release scripts now; complete sidecar bundling in
  the platform release flow after infrastructure approval

### CI/CD treatment

- Release build scripts, packaging templates, and workflow examples live in-repo
- Actual `.github/workflows/*` application remains a governed infrastructure step per ADR-006

## Consequences

- Foundry gets a stable local launch contract that both Burrito and Tauri can consume
- Distribution automation becomes scriptable and reviewable before platform-owned workflow
  files are applied
- We avoid adding an unnecessary caching layer before demand justifies it
- The desktop app stays a wrapper around the existing Phoenix UI instead of creating a
  second frontend/backend split
- The desktop app now depends on `tauri-plugin-shell` so it can launch and supervise the
  embedded Foundry sidecar during startup
