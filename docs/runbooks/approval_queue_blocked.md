# Runbook: Blocked Approval Queue

**Applies to:** `:sensitive` and `:compliance` change proposals awaiting approval  
**Reactor/Component:** `Foundry.Approvals` workflow  
**Last tested:** —  
**Escalation:** See escalation chain below

---

## Symptoms

- A `:sensitive` or `:compliance` proposal has been waiting for approval beyond the SLA
- The designated approver is unavailable (out of office, incident response, offboarding)
- A hotfix needs to reach production but is blocked on a `:sensitive` approval
- A `:compliance` change is blocked because the compliance officer is unavailable

---

## SLA Definitions (configure in manifest)

```elixir
approval_sla: [
  structural:  nil,          # no SLA — auto-apply or casual review
  behavioral:  hours: 24,    # domain lead reviews within 24h
  sensitive:   hours: 4,     # sensitive lead + one other within 4h
  compliance:  hours: 48     # compliance officer within 48h
]
```

The operations board shows proposals that have exceeded their SLA in amber/red.

---

## Step 1: Confirm the Proposal Is Genuinely Blocked

```bash
mix foundry.approvals.status --pending

# Output shows:
# - proposal_id
# - change_class
# - created_at
# - waiting_for: ["finance-lead@company.com", "platform-lead@company.com"]
# - sla_deadline
# - sla_exceeded: true/false
```

If the approver simply hasn't seen the notification: resend it.
```bash
mix foundry.approvals.notify --proposal-id <id>
```

If the approver is genuinely unavailable, proceed to Step 2.

---

## Step 2: Identify the Delegation Path

Check the manifest for a configured delegate:

```elixir
# .foundry/manifest.exs
approvers: [
  sensitive_lead: "finance-lead@company.com",
  sensitive_lead_delegate: "cto@company.com",   # used when sensitive_lead unavailable
  compliance_officer: "compliance@company.com",
  compliance_officer_delegate: "legal@company.com"
]
```

If a delegate is configured: notify the delegate. Their approval carries the same weight
as the primary approver's. The audit log records which role approved and in what capacity.

If no delegate is configured: proceed to Step 3.

---

## Step 3: No Delegate Configured

**For `:sensitive` proposals (non-emergency):**
Wait for the approver to return. There is no override path for non-emergency sensitive
changes. If this is causing release delays frequently, add a delegate to the manifest
(this is a `:structural` change to the manifest itself).

**For `:sensitive` proposals (genuine emergency / production incident):**
Two conditions must both be true before an emergency override is considered:
1. There is a production incident actively causing customer harm or data loss
2. The fix has been verified by someone with equivalent domain knowledge

If both conditions are met:
1. The on-call engineer and the platform lead must both approve in writing (Slack/email)
2. The override is logged manually in the audit log with: proposal ID, approvers, reason, timestamp
3. The compliance officer (or delegate) must review the override within 24 hours
4. An ADR review is triggered to assess whether the approval policy needs updating

This is the emergency break-glass path. It requires two humans. It is always audited.
It is not a mechanism for bypassing approval because it's inconvenient.

**For `:compliance` proposals:**
There is no emergency override path. Compliance changes that bypass the compliance officer
create regulatory exposure that is worse than the delay. Wait for the compliance officer
or their designated delegate.

---

## Step 4: After Resolution

If the blockage was caused by a manifest misconfiguration (no delegate, wrong contact):
- Update the manifest (`sensitive_lead_delegate`, notification channels)
- This is a `:structural` change — no special approval needed

If the blockage revealed an organisational gap (no one with the right authority available):
- Document it as a finding
- The compliance officer and platform lead review the approval policy at the next
  governance review cycle

---

## Escalation Chain

```
Proposal blocked → notify designated approver
  → SLA exceeded → notify delegate (if configured)
    → delegate unavailable → platform lead + on-call engineer
      → genuine emergency → break-glass (two humans, always audited)
        → compliance officer review within 24h of break-glass use
```

For `:compliance` proposals: escalation stops at compliance officer.
No break-glass path exists for compliance changes.