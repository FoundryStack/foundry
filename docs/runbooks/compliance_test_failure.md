# Runbook: Compliance Test Failure

**Applies to:** Compliance-tagged E2E tests (`@tag :compliance`)  
**Reactor/Component:** CI compliance gate + `mix foundry.compliance.check`  
**Last tested:** —  
**Escalation:** Compliance officer → Platform lead

---

## Symptoms

- CI fails at the compliance gate with `:compliance_test_failed`
- Compliance dashboard shows a red requirement (e.g., `RG-UK-002: ❌ FAIL`)
- `mix foundry.compliance.check` reports failing tagged tests
- A release is blocked pending compliance resolution

---

## Step 1: Identify Which Requirement Failed

```bash
mix foundry.compliance.check --json | jq '.failures'

# Output includes:
# - requirement_id: "RG-UK-002"
# - test_module: "MyAppE2E.Compliance.SelfExclusionTest"
# - test_name: "self-excluded player cannot log in during exclusion period"
# - last_passed: "2026-02-15"
# - failure_reason: "element not found: [data-action='self-exclude']"
```

---

## Step 2: Classify the Failure

**Class A — Test infrastructure failure** (the test itself is broken, not the feature)

Signs: `failure_reason` mentions missing `data-*` selector, timeout, or seed data issue.
The feature likely still works; the test can't reach it.

```bash
# Run the test locally with headed browser to see what's happening
mix test test/e2e/compliance/self_exclusion_test.exs --seed 0

# Common causes:
# - UI component was refactored and data-* attribute was renamed/removed (INV in ADR-007)
# - Test seed data generator changed and the test's preconditions no longer hold
# - A LiveView route changed
```

Fix: update the test selector or generator. This is a `:structural` change — no compliance
officer approval needed, but the compliance officer must be notified that the test was
temporarily failing before being fixed.

**Class B — Feature regression** (the compliance requirement is actually not met)

Signs: the test reaches the UI correctly but the assertion fails (wrong error message,
wrong behaviour, wrong state in database).

This is a genuine compliance failure. **Do not bypass the CI gate.**

Proceed to Step 3.

---

## Step 3 (Class B): Assess Scope and Notify

1. Identify which code change introduced the regression:
   ```bash
   git log --oneline -20
   git bisect start HEAD <last-green-commit>
   ```

2. Notify the compliance officer immediately. Do not wait for the root cause analysis.
   The notification must include: requirement ID, description of observed behaviour,
   the commit range under investigation.

3. Assess whether the regression affects live production:
   - If the feature is not yet in production: block the release, fix in development
   - If the feature IS in production and is now broken: this is a live compliance incident —
     escalate to the compliance officer for regulatory notification obligations

---

## Step 4 (Class B): Fix and Re-Certify

The fix is a `:compliance` class change (ADR-005). It requires:
- Compliance officer approval
- An ADR or ADR update explaining what broke and how it was fixed
- The compliance test must pass in CI before the fix is considered complete
- The compliance dashboard must show the requirement green before release proceeds

```bash
# After fix is applied and CI passes:
mix foundry.compliance.check
# All requirements must show ✅ PASS before release gate is cleared
```

---

## Step 5: Post-Incident

After resolution, the compliance officer reviews:
- Was the regression introduced by a `:behavioral` change that should have triggered
  a compliance review but didn't? If so, the classifier rules in ADR-005 may need updating.
- Was the E2E test's coverage adequate? Did it catch the regression at the right layer?
- Update the compliance dashboard's `last_reviewed` date for the affected requirement.

---

## What Is Never Acceptable

- Disabling or skipping a compliance-tagged test to unblock a release
- Merging a change that makes a compliance test pass by weakening the assertion
- Releasing to production while a compliance requirement is red, even temporarily

If there is business pressure to release despite a compliance failure, the decision
must be made by the compliance officer with documented reasoning — not by a developer
commenting out a test.