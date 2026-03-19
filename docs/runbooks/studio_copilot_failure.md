# Runbook: Copilot Engine Failure

**Applies to:** Foundry Studio copilot engine  
**Reactor/Component:** `Foundry.Copilot.Engine`  
**Last tested:** —  
**Escalation:** Platform team

---

## Symptoms

- Copilot returns "I was unable to build context for this request"
- Copilot proposals are missing impact analysis or compliance information
- Copilot generates code that fails `mix foundry.lint.all`
- Copilot produces Ash 2.x syntax in an Ash 3.x project

---

## Step 1: Identify the Failure Class

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

## Step 2: LLM API Error

```bash
# Verify API key is configured
mix foundry.config --check=llm_api_key

# Check Anthropic status page (agent cannot do this — human must check)
# https://status.anthropic.com

# If API is down: the copilot is unavailable. 
# Visualization panels remain functional.
# Developers can still use CLI tools directly:
mix foundry.context <Module>
mix foundry.lint.all
mix foundry.compliance.check
```

The copilot is a convenience layer over these tasks. It is not the only way to use the platform.

---

## Step 3: Stack Version Mismatch

The copilot failed to include correct stack versions in the LLM context.

```bash
# Regenerate version manifest
mix foundry.versions.refresh

# Verify output includes all critical libraries
mix foundry.versions.check
# Expected: ash, ash_double_entry, ash_state_machine, phoenix, oban
# If any are missing: add them to config/foundry_studio.exs under :version_tracking
```

---

## Step 4: ADR Contradiction Detected

The proposal was blocked because it contradicts an ADR. This is **correct behaviour**, not a failure.

1. Read the ADR cited in the block message
2. Determine if the ADR is outdated or if the user's intent needs to be revised
3. If ADR is outdated: update it (human authors the ADR update, copilot cannot)
4. If user intent conflicts with a correct ADR: explain the constraint to the user

ADR contradictions should **never** be overridden by disabling the ADR check.
If a constraint is wrong, update the ADR through the proper process.

---

## Step 5: Proposals Generating Invalid Code

If approved proposals consistently fail lint after application:

```bash
# Run the validation step manually on the last proposal
mix foundry.scaffold.validate --last-proposal

# This runs the same lint + semantic checks as the pre-approval flow
# If this passes but post-application fails, the apply step has a bug
# File an issue with the diff output attached
```

Common causes:
- The Igniter operation is outdated and generates deprecated DSL syntax (update the operation module)
- The project has a custom lint rule that isn't covered by the standard validation pipeline (add it to `config/foundry_studio.exs` under `:custom_lint_rules`)

---

## Scaffold Operation Failure

**Symptoms:**
- Copilot shows "Scaffold operation failed" in the review panel
- `mix foundry.scaffold.last-error` reports a non-zero exit
- Proposed diff is empty or malformed
- Applied change results in a compilation error

### Step A: Read the Operation Error

```bash
mix foundry.scaffold.last-error
# Output includes:
# - operation: which Op.* or raw Igniter call failed
# - step: which pipeline step failed
# - reason: the Igniter error or AST parse error
# - dry_run_output: partial diff before failure
```

### Step B: AST Parse Error

If `reason` contains "failed to parse module" or "zipper could not find target":

```bash
# The target module may have a syntax error preventing Igniter from reading it
mix compile --force 2>&1 | head -30
# Fix compilation errors first; the scaffold operation cannot apply to a broken module
```

### Step C: DSL Option Outdated

If `reason` contains "unknown DSL option" or "deprecated key", the pattern example or
ExDoc the agent used references a changed DSL surface.

```bash
mix foundry.versions.check
mix foundry.exdoc Ash.Resource.Attribute --function allow_nil?
# Compare against the failing operation's generated source
# Workaround: make the change manually using the CLI pattern the operation would generate
```

### Step D: Dry-Run Passes, Apply Fails

```bash
ls -la lib/   # check file permissions
mix foundry.scaffold.retry --last-operation
```

If retry also fails, apply the dry-run diff manually:

```bash
mix foundry.scaffold.last-error --dry-run-diff > /tmp/proposed.patch
patch -p1 < /tmp/proposed.patch
mix compile
mix foundry.lint.all
```

---

## Escalation

If none of the above resolves the issue:
1. Export the failing request context: `mix foundry.copilot.export --last-request`
2. Post to the `#foundry-studio-platform` channel with the exported context attached
3. Do not share the full LLM prompt in public channels — it may contain project-sensitive domain information