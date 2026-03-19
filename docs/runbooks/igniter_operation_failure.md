# Runbook: Igniter Operation Failure

**Status:** Content merged into `docs/runbooks/studio_copilot_failure.md` §Scaffold Operation Failure.

**Applies to:** All scaffold operations — Igniter pipeline failures during proposal generation
**Last tested:** —
**Escalation:** Platform team

---

## Symptoms

- Copilot shows "Scaffold operation failed" in the review panel
- `mix foundry.scaffold.last-error` reports a non-zero exit
- Proposed diff is empty or malformed
- Applied change results in a compilation error

---

## Step 1: Read the Operation Error

```bash
# Check the Studio logs for the last copilot request
mix foundry.logs --tail=50 --filter=copilot

# Match the error code to the step below:
# :context_build_failed     → see studio_ux_degradation.md Step 3
# :igniter_operation_failed → see §Scaffold Operation Failure in this file
# :llm_api_error            → Anthropic API error (proceed to Step 2)
# :version_mismatch         → Stack version detection failed (proceed to Step 3)
# :adr_contradiction        → Proposal contradicts an ADR (proceed to Step 4)
```

---

> **This file is retained for git history only.** For project server / context build failures,
> see `docs/runbooks/studio_ux_degradation.md` Step 3. For scaffold operation failures,
> see `docs/runbooks/studio_copilot_failure.md` §Scaffold Operation Failure.