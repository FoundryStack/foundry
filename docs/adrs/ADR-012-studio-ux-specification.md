# ADR-012: Studio UX Specification

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

ADR-008 establishes the read-only visualization paradigm and names the five panels and
command palette but does not specify how they render, what their empty and loading states
look like, how users navigate, how the approval and notification UX works, or what the
performance and accessibility requirements are. Without this specification, Phase 2 and
Phase 3 implementations diverge from intent.

This ADR also corrects a naming and layout decision implicit in ADR-008's framing:
what ADR-008 called the "Copilot Panel" is now the **Activity Feed** — a persistent right
sidebar combining a chronological event stream with a chat input at the bottom. This is a
naming and layout change only. The governance model (copilot engine is the only change
interface) is unchanged.

This ADR covers the Studio UI layer only. Copilot agent behaviour is ADR-013.
Proposal lifecycle and approval workflow mechanics are ADR-014.

---

## Decision: Command Palette

**Keyboard shortcut: `Cmd+K` (macOS) / `Ctrl+K` (Windows/Linux).**

> Note: ADR-008 referenced `Cmd+P`. That was incorrect. The canonical shortcut is `Cmd+K`.
> All documents referencing `Cmd+P` should be updated to `Cmd+K`.

Opens a floating modal overlay, centred, over the current view. Does not navigate away.

**The palette is a navigation tool, not an operation picker.** Operation selection is the
engine's responsibility (ADR-013 §Intent Classification). Users express intent as natural
language in the Activity Feed — they do not choose `Op.*` modules. Exposing the internal
operation catalogue in the palette would require users to understand Foundry's taxonomy
before they can use it, which defeats the purpose of intent-based interaction.

**Structure (top to bottom):**
1. Search input — autofocused on open
2. **Recent** — last 5 navigations or Activity Feed interactions (LiveView session state, not persisted across sessions)
3. **Navigate** — jump to module, domain, ADR, runbook, or compliance requirement by name or ID

Keyboard: `↑`/`↓` to move, `Enter` to select, `Escape` to dismiss. Typing filters both sections simultaneously.

**Navigate entries resolve to:**
- Module name → opens that node in the System Map with the detail drawer open
- Domain name → centres the System Map on that domain cluster
- ADR-XXX → opens ADR text overlay
- RG-XXX → scrolls Compliance Matrix to that requirement row
- Runbook name → opens runbook text overlay

**Phase availability:** Present from Phase 2. The Activity Feed (where changes are initiated)
is available from Phase 3.

---

## Decision: System Map Interaction Details

### Layout

Nodes are clustered by domain. Domain clusters are labeled with the domain name.
Node size is uniform — encoding data in node size creates cognitive overhead that
outweighs the information density benefit at 50+ nodes.

Nodes use colour to encode type:
- Resource → blue
- Transfer/Reactor → purple
- Rule → amber
- Blueprint → green
- Oban worker → grey

### Navigation and Selection

**Node click:** Opens a detail drawer from the **left edge of the map**, sliding over the
map content. Width: 360px. The selected node is highlighted with a ring indicator. The
drawer does not affect the Activity Feed sidebar on the right.

**Rationale for left-side drawer:** The Activity Feed occupies the right side permanently.
A right-side detail drawer would collide spatially with the feed and force users to shift
attention across the full screen width to relate node detail to ongoing conversation. Placing
the drawer on the left keeps the subject (node detail) proximate to the map it describes,
while the feed (ongoing commentary) remains stable on the right. This follows the
split-attention principle: related information grouped spatially reduces cognitive load.

**Detail drawer contents (top to bottom):**
1. Module name + type badge
2. `@moduledoc` text (truncated at 300 chars with "Show more" expansion)
3. Attributes table: name, type, `@description` (truncated), sensitive flag
4. Actions list with change class
5. Compliance requirements — each RG-* ID is a link that scrolls the Compliance Matrix to that row
6. Linked ADRs — each ADR-XXX is a link that opens the ADR text in a full-screen overlay
7. Test coverage badge: green (all present), amber (partial), red (missing)
8. Runbook link (if declared via `@runbook`)
9. **Contextual intent shortcuts** (bottom of drawer, above close button) — see §Contextual Intent Shortcuts

**Edge labels:** Relationship type shown on hover only. Default state is edges without labels to keep the map readable. Hovering an edge shows: source module → relationship type → target module.

### Search and Filter

Top-bar search field visible above the map. Accepts:
- Module name fragment (e.g., "Wallet")
- Domain name (e.g., "Finance")
- Compliance requirement ID (e.g., "RG-UK-014") — highlights all modules linked to that requirement
- Type filter (e.g., "transfers") — highlights all nodes of that type

Non-matching nodes dim to 20% opacity. Matching nodes remain at full opacity and are
brought to the foreground. Search is client-side (no round-trip) — the full graph data
is already loaded.

### Contextual Intent Shortcuts

The bottom of every node detail drawer shows a small set of intent shortcuts relevant to
that node type. These are not operation names — they are plain-language descriptions of
the most common next actions for this kind of module.

| Node type | Intent shortcuts |
|---|---|
| Resource | "Add attribute", "Add action", "Add policy", "Generate tests", "Link compliance requirement" |
| Transfer / Reactor | "Add rule", "Add step", "Generate tests", "View runbook" |
| Rule | "Add jurisdiction clause", "Generate tests", "Link compliance requirement" |
| Blueprint | "Add eligibility clause", "Generate tests" |
| Oban worker | "Generate tests", "View runbook" |
| Compliance gap (Matrix) | "Implement this requirement", "Add E2E test" |
| Test coverage gap | "Generate missing test" |

**Clicking a shortcut** sends a pre-formed intent message into the Activity Feed input —
the user sees it appear in the feed as if they had typed it. The engine receives structured
context (the module name is already known from the drawer) so classification confidence is
always HIGH and the clarifying question path is skipped (ADR-013).

The shortcuts are the primary entry point for routine development work. Natural language
in the Activity Feed input is the entry point for complex, multi-module, or ambiguous intent.
Both paths feed the same engine.

---

## Decision: Activity Feed (Persistent Right Sidebar)

The Activity Feed is the primary interface for interacting with the copilot engine and
monitoring system activity. It is visible by default and occupies the right side of the
Studio layout.

**What ADR-008 called "Copilot Panel" is now the Activity Feed.** The governance model
is unchanged — all changes still go through the copilot engine. The naming change reflects
that the surface is primarily an event stream with a chat input, not primarily a chat
interface with event notifications bolted on.

### Layout

```
┌──────────────────────────┐
│  Activity Feed      [×]  │  ← hide toggle (Cmd+\ restores)
├──────────────────────────┤
│                          │
│  [event card]            │
│  [event card]            │
│  [proposal card] ──────► │  click → opens review panel (bottom sheet)
│  [CI result card]        │
│  [copilot response card] │
│  [event card]            │
│                          │  ← scrollable, newest at bottom
├──────────────────────────┤
│  [input box]         [↑] │  ← always visible, autofocused on Studio load
└──────────────────────────┘
```

**Width:** 320px fixed. Not resizable — a fixed width keeps the map region stable and
predictable. If the user hides the feed, the map expands to fill the full width.

**Default state:** Visible. Persists across page navigations within the session.
Persists across sessions (hidden/visible preference stored in browser localStorage — this
is UI preference state, not application data, so localStorage is appropriate here).

### The Event Stream

The stream is a chronological list of cards, newest at the bottom. All system events appear
here in one place. The user never needs to check a separate notifications panel — the feed
is the single place for everything.

**Card types:**

| Event | Card appearance |
|---|---|
| Copilot response to a question | Text card with source citations. Compact — expandable on click. |
| Proposal ready for review | Proposal card: title, change class badge, "Review →" button. Clicking opens review bottom sheet. |
| Approval requested | "Your approval needed: [title]" card with "Review →" button. |
| Approval received | "[Approver] approved [title]" card. Green indicator. |
| Proposal applied + committed | "[title] applied. Commit: [sha]" card with CI link. |
| Proposal stale | "[title] is stale" card with "Regenerate" inline button. |
| CI result | Pass/fail card with link to CI run. |
| Compliance test failed | Red card: "[RG-XXX] failed in CI" with "View →" button linking to Compliance Matrix row. |
| Runbook stale | "[runbook] not tested in N days" amber card. |
| Error (any engine error code) | Error card with code, message, and runbook link. |

**Contextual shortcut submissions** appear in the stream as a user message card (showing
the pre-formed intent) followed by the copilot's response card. The user can see exactly
what was sent and what the engine understood.

**History:** The feed shows the last 200 events in the current session. Older events are
accessible via `mix foundry.audit.export`. The feed is not a permanent record — the audit
log (ADR-014) is the permanent record.

### The Chat Input

Always visible at the bottom of the feed. Autofocused when the Studio loads.

Single-line input that expands to multiline on Shift+Enter. Plain Enter sends.
Placeholder text: "Ask a question or describe a change…"

The input does not need to be "activated" — it is always ready. The user does not
select a mode before typing. The engine classifies intent from the message content (ADR-013).

**Relationship to contextual shortcuts:** Shortcuts write into this input and submit
automatically. The user sees the message appear in the feed stream as if they had typed it.
This means the feed is a complete record of all interactions — there is no hidden channel
where shortcuts bypass the visible history.

### Hiding the Feed

`Cmd+\` (macOS) / `Ctrl+\` (Windows/Linux) toggles the feed. A slim tab on the right
edge of the map area shows when the feed is hidden: a vertical label "Activity" with an
unread count badge if there are unseen events.

The hide state is appropriate during deep system map exploration where screen width matters.
The feed is not dismissable permanently — it is a hide/show toggle.

### Empty and Loading States

**Loading:** Skeleton graph showing domain cluster outlines and placeholder nodes without
content. Appears after a 200ms delay to avoid a flash on fast loads. Loading text:
"Reading project structure…"

**Empty (no compiled modules):**
```
No modules found.
Run `mix compile` in your project directory to populate the system map.
```
Copy-to-clipboard button on the command.

**Compile error state:** If `mix foundry.project.context` returns non-zero (compile failure), the map shows:
```
The project has compilation errors. Fix these before the system map can render:
[compiler error output, truncated to 20 lines with "Show full output" expansion]
```

---

## Decision: Review Panel Rendering

The review panel opens as a **bottom sheet** when a proposal is ready. It slides up from
the bottom of the viewport, defaulting to 50% of viewport height with a drag handle for
resizing. The System Map (or active panel) remains visible above it. The Activity Feed
sidebar remains visible to the right.

**Rationale for bottom sheet over right drawer:** Diffs require horizontal space. A right
drawer at 360–400px forces horizontal scrolling on any non-trivial diff. A full-width
bottom sheet gives the diff its natural reading direction. The map stays oriented above,
letting the user see which node the proposal relates to without closing the review panel.
Spatially: subject (map) above, diff (what would change) below, feed (commentary) to the
right — each in a stable, non-colliding region.

**The detail drawer (left) and review panel (bottom) can be open simultaneously.** A user
may want to read node detail while reviewing a proposal that touches it. These surfaces
serve different purposes and do not compete for the same screen region.

### Layout

```
┌──────────────────────────────────┬──────────────┐
│                                  │              │
│   System Map (or active panel)   │   Activity   │
│                                  │   Feed       │
│   ← detail drawer (if open)      │              │
│                                  │              │
├──────────────────────────────────┤              │
│ ▲ [drag handle]                  │              │
│ [Proposal title] [:behavioral]   │              │
│ Code Changes │ Migration │ Lint │ Impact        │
│                                  │              │
│  [diff renderer — full width]    │              │
│                                  │              │
│ Approvals: ⏳ domain-lead@…      │              │
│ [Request Approval][Regenerate]   │              │
└──────────────────────────────────┴──────────────┘
```

**Default height:** 50% of viewport. Minimum: 200px (shows header + one diff line).
Maximum: 80% (preserves some map context above). Height preference is persisted in
LiveView session state — not across sessions (avoids a user leaving it maximised and
forgetting on the next session).

**Dismiss:** Close button top-right of the sheet, or drag handle dragged to minimum height.
Dismissing does not reject the proposal — it returns the proposal to its current state
(DRAFT or PENDING_REVIEW). The proposal remains accessible from the Activity Feed.

**Migration tab:** Only shown when the proposal includes a migration diff. The migration
diff is rendered in the same diff renderer as code changes, with a header: "Database
migration — `priv/repo/migrations/[timestamp]_[name].exs`".

### Diff Renderer

Unified diff format. Line-level red/green backgrounds. Line numbers shown on both sides.
Syntax highlighting for Elixir. Long diffs (>200 lines visible) are collapsed with
"Show [N] more lines" inline expansion — the first 100 and last 100 lines are always shown.

The diff renderer is read-only. There is no inline editing. Changes to a proposal require
dismissing and regenerating.

### Lint Tab

Three sections rendered as collapsible groups:
- **Errors** (block apply — shown expanded by default if any exist): rule ID, file path, line number, message, link to the ADR or INV that defines the rule
- **Warnings** (non-blocking — shown collapsed by default): same structure
- **Info** (collapsed by default)

A green "All checks passed" state when no errors or warnings.

### Impact Tab — "Impact Analysis" Defined

**Impact analysis** is the computed set of side-effects a proposal has beyond the immediate
diff. It is deterministic — produced by the agent via targeted bash queries against the
system map graph (`mix foundry.context.all`), not LLM inference and not a separate module.

Impact analysis includes:
- **Recompile scope:** modules that import or alias the changed module (will recompile on next `mix compile`)
- **Test attention:** test files that reference the changed module directly
- **Compliance attention:** RG-* requirements linked to the changed module — reviewer should verify the requirement is still satisfied
- **Runbook attention:** runbooks that reference the changed module — may need updating
- **Pending migrations:** count of pending migrations after this proposal would be applied

Impact analysis is shown as a structured list, not prose. Each item links to the relevant
file or panel. An empty impact analysis (no side-effects) shows: "No downstream effects detected."

### Approval Footer

**`:structural` (auto-apply configured):** "Approved on apply." Apply button is active.

**`:structural` (auto-apply not configured):** "Awaiting approval from any developer."
"Approve and Apply" button visible to any authenticated user.

**`:behavioral`:** "Awaiting approval from: domain lead (domain-lead@company.com)."
The approver sees an "Approve" button in their approval queue. The requester sees
a "Notify Approver" button to resend the notification.

**`:sensitive`:** "Awaiting dual approval. (1/2) Sensitive lead (sl@company.com) ⏳.
(2/2) Any second approver ⏳." Each approver slot updates independently as approvals arrive.

**`:compliance`:** "Awaiting compliance officer (compliance@co.com). ADR link required."
The ADR link field is a text input accepting an ADR ID (e.g., "ADR-005") or a partial
title. Autocompletes against existing ADRs. Validated: the referenced file must exist at
`docs/adrs/ADR-XXX-*.md` before the "Submit for Approval" button activates.
If the ADR does not yet exist, the field shows a warning: "ADR not found. The compliance
officer must confirm the ADR will be created before approving." The proposal can still be
submitted — the compliance officer makes the final judgment.

There is no inline ADR creation in the review panel. ADRs are authored as files and committed.

### Stale Proposal Banner

Full-width amber banner pinned to the top of the review panel when a blob hash mismatch
is detected (ADR-009):

```
⚠ Stale — lib/my_app/finance/wallet.ex was modified since this proposal was generated.
[Regenerate]
```

"Regenerate" re-runs the original operation against the current codebase. If the resulting
diff is identical to the stale one, the banner clears and the proposal proceeds. If the
diff differs, a new diff is shown for review.

---

## Decision: Approval Tracking

Pending approvals appear in the Activity Feed as proposal cards. No separate Approvals
view is needed for the common case — the feed surfaces everything in real-time.

**For users who need a full queue view** (approvers managing multiple pending proposals):
`Cmd+K` → type "approvals" opens a secondary list view showing all PENDING_REVIEW proposals
sorted by SLA deadline. This is an overflow surface — most users will not need it.

**Queue view layout:** Table of all PENDING_REVIEW proposals.
Columns: Proposal title | Change class | Requester | Waiting | SLA status | Your action.

SLA status: green (within SLA), amber (>50% of SLA elapsed), red (SLA exceeded).
Visual indicators only — the system does not auto-escalate.

**"Review →" action:** Opens the review bottom sheet for that proposal. The approval
button is in the review panel footer, not in the queue row.

**Visibility:** All proposals in PENDING_REVIEW or later are visible to all project users.
DRAFT proposals are visible only to the requester. Non-approvers see proposals in
read-only mode without the approval button. This allows any developer to see what is
in-flight before starting work that might conflict (ADR-009, ADR-014 §Proposal Visibility).

---

## Decision: Notifications

All in-Studio notifications appear as event cards in the Activity Feed. There is no separate
notification inbox or bell dropdown — the feed is the inbox.

**Unread indicator:** When the Activity Feed is hidden (`Cmd+\`), the slim "Activity" tab
on the right edge shows an unread count badge. When the feed is visible, events are considered
read as they scroll into view.

**Notification types** (appear as feed cards per §Activity Feed card types above):

| Type | Card colour | External delivery (INV-010) |
|---|---|---|
| `approval_requested` | Blue | Slack / email per manifest |
| `approval_complete` | Green | None (in-feed only) |
| `proposal_stale` | Amber | None (in-feed only) |
| `sla_exceeded` | Red | Slack / email per manifest |
| `compliance_test_failed` | Red | Slack / email per manifest |
| `runbook_stale` | Amber | Slack / email per manifest |

External delivery (Slack/email) is configured per INV-010. In-Studio delivery is always
the Activity Feed. External notifications are fire-and-forget — they are not persisted.
In-feed event cards live in ETS (LiveView session state) — last 200 events visible.

---

## Decision: Onboarding / Bootstrap UX

When `mix foundry.studio` is run in a project with no spec-kit (no `AGENTS.md` at project root):

**Step 1 — Welcome overlay:** Full-screen overlay with two options:
- **"Initialize spec-kit"** — runs `mix foundry.spec_kit.init` in a terminal panel embedded in the overlay, shows generated files as they are created. On completion: "Done. Your spec-kit is ready." with a "Open Studio" button that dismisses the overlay and loads the system map.
- **"Continue without spec-kit"** — dismisses the overlay. Studio runs in reduced mode: no Compliance Matrix, no copilot ADR contradiction checking, no runbook links. A persistent amber banner at the top of the Studio indicates reduced mode: "No spec-kit found. Some features are disabled. Run `mix foundry.spec_kit.init` to enable them."

**Reduced mode limitations (no spec-kit):**
- System Map: functional
- Compliance Matrix: shows "No compliance requirements declared"
- Copilot: functional for questions; proposals allowed but ADR contradiction check is skipped; a warning is shown on every proposal: "No spec-kit. This proposal has not been checked against ADRs or invariants."
- Operations Board: functional
- Test Coverage Map: functional

**When spec-kit exists but project does not compile:**
System Map shows the compile error state (described above). All other panels show:
"System map unavailable — project has compilation errors."

---

## Decision: Empty and Loading States (All Five Panels)

| Panel | Loading state | Empty state |
|---|---|---|
| System Map | Skeleton cluster outlines + placeholder nodes. "Reading project structure…" | "No modules found. Run `mix compile`." |
| Compliance Matrix | Skeleton table rows. "Loading compliance data…" | "No compliance requirements declared. Add regulation files to `docs/regulations/` to populate this matrix." |
| Operations Board | Skeleton rows. "Loading operations data…" | "No runbook links found. Add `@runbook` declarations to Reactor modules to populate this board." |
| Test Coverage Map | Skeleton bar charts. "Loading coverage data…" | "No test results found. Run `mix test` to populate coverage data." |
| Activity Feed | Skeleton cards while initial context loads. "Connecting…" | Input ready immediately. Feed shows: "Ask a question or describe a change to get started." |

Loading states appear after a 200ms delay. Below 200ms, no loading indicator is shown.

---

## Decision: Performance Budgets

These are the target performance bounds. If a measure exceeds its bound, it is a bug to
be filed, not a design decision to be revisited.

| Metric | Budget |
|---|---|
| System Map initial render (≤50 modules) | ≤ 1 second from page load |
| System Map initial render (50–200 modules) | ≤ 3 seconds from page load |
| Node click → detail drawer open | ≤ 200ms (graph data already loaded) |
| `mix foundry.context` subprocess call | ≤ 2 seconds; show "Retrieving context…" if >500ms |
| Copilot first streamed token | ≤ 5 seconds from message send |
| Review panel diff render | ≤ 500ms for diffs up to 500 lines |
| Command palette open | ≤ 100ms |
| Panel-to-panel navigation | ≤ 200ms (LiveView navigation, no full reload) |

---

## Decision: Accessibility

WCAG 2.1 AA. Non-negotiable. Specific requirements:

- All interactive elements are keyboard-navigable in a logical tab order
- Color is never the sole state indicator. Every color-coded state also has an icon and text label (e.g., lint errors: red background + ⛔ icon + "Error" label, not red background alone)
- The diff renderer exposes `role="region"` with `aria-label="Code changes"` and `aria-label="Migration changes"` for screen reader navigation
- The system map D3 graph provides a table view alternative (togglable) that lists all nodes and edges in a navigable table — the SVG graph itself is not screen-reader accessible
- Focus is managed correctly when the command palette opens and closes (focus returns to the triggering element on close)
- The copilot response stream is announced to screen readers when complete via `aria-live="polite"`

---

## Decision: Responsive and Mobile

The Studio is a developer tool. Minimum supported viewport: **1280px wide**.

No mobile optimization in v1. On viewports below 1280px, the Studio displays:
"Foundry Studio requires a minimum viewport of 1280px. Please use a desktop browser."

This is an accepted constraint, not an oversight. The system map and review panel require
sufficient horizontal space to be usable. Revisit in v2.

---

## Decision: Data Retention

Storage implementation for all Foundry state is specified in ADR-015.
The retention periods below are the requirements; ADR-015 defines how they are met.

| Data type | Retention period | Storage | Notes |
|---|---|---|---|
| Approved proposal records | 7 years | `.foundry/proposals/` in git | Git history provides integrity |
| Rejected / dismissed proposals | 90 days | `.foundry/proposals/` in git | `mix foundry.proposals.purge` removes files older than 90 days and commits the deletion |
| Audit log (`:sensitive`, `:compliance` approvals) | Indefinite | `.foundry/audit.jsonl` in git | Append-only. Git history is the integrity record. Never purged. |
| Approval records (approver, timestamp, diff hash) | 7 years | `.foundry/audit.jsonl` in git | Part of the audit chain — each approval is one JSONL line |
| Activity Feed event history | Session only | ETS (LiveView state) | Not persisted. Feed shows last 200 events in session. |
| LLM prompts and responses | Not stored | — | Privacy. Only error codes and structured metadata are logged to telemetry. |

**Retention is git history.** There is no database to back up. The project's existing git
remote is the backup. Regulatory inspection uses `git log -p .foundry/audit.jsonl` or
`mix foundry.audit.export --from=<date> --to=<date>`.

**Draft proposals** are written to `.foundry/proposals/prop_<id>.draft.json` on disk but
are not committed. If the Studio process restarts before submission, the draft is lost.
Regeneration is cheap — this is acceptable.

**The `.foundry/` directory** is committed to the project repository. Draft files
(`.draft.json`) are gitignored. Committed proposal files (`.json`) are version-controlled.

---

## Decision: Studio Layout

The canonical Studio layout at 1280px+ viewport:

```
┌─────────────────────────────────────────────┬──────────────────────┐
│  [top bar: panel tabs + search + Cmd+K]     │                      │
├─────────────────────────────────────────────┤   Activity Feed      │
│                                             │   320px fixed        │
│   Main panel area                           │                      │
│   (System Map, Compliance Matrix,           │   [event stream]     │
│    Operations Board, Test Coverage Map)     │   [event stream]     │
│                                             │   [event stream]     │
│   ← left detail drawer (360px)             │   [event stream]     │
│     slides over map on node click           │                      │
│                                             │   ──────────────     │
│                                             │   [input box]    [↑] │
├─────────────────────────────────────────────┤                      │
│  ▲ Review Panel (bottom sheet, 50% default) │                      │
│  [proposal diff — full width of left area]  │                      │
└─────────────────────────────────────────────┴──────────────────────┘
```

Key spatial properties:
- **Left:** detail drawer — contextual info about the selected node, proximate to the map
- **Right:** Activity Feed — persistent, stable, never displaced by other surfaces
- **Bottom:** review panel — full-width diff reading space, map stays oriented above
- **Top:** panel navigation — global, always accessible

The three surfaces (detail drawer, review panel, Activity Feed) can all be open
simultaneously without collision. This is the target state during active development:
node detail visible left, diff being reviewed below, feed showing context right.

---

## Consequences

- `Cmd+K` is the canonical palette shortcut — navigation only, no operation picker
- The palette does not expose `Op.*` modules — operation selection is the engine's responsibility (ADR-013)
- The Activity Feed sidebar uses `localStorage` for hide/show persistence — this is UI preference state, not application data. This is the one permitted exception to the no-localStorage rule in artifacts; it applies only to this single boolean preference.
- The left detail drawer and bottom review panel can be open simultaneously — they occupy non-colliding regions
- The Activity Feed is the single surface for all in-Studio notifications — there is no separate bell dropdown or notification inbox
- The impact analysis is produced by the agent via bash traversal of `mix foundry.context.all` output — deterministic, not LLM-generated, no separate module
- The system map table view alternative is required for WCAG compliance — the D3 SVG graph alone is insufficient
- Data retention periods assume a financial/regulated platform target. Projects in other domains may override the defaults in `manifest.exs` under `data_retention:`
- The 7-year audit log retention is enforced at the application layer — infrastructure teams must ensure the underlying storage is not purged
- All references to "Copilot Panel" in other spec-kit documents should be read as "Activity Feed" — ADR-008 will be updated to reflect this rename