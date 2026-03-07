This is a deep design problem worth thinking through carefully before writing a line of code.

## Reasoning: What You're Actually Asking

You want the graph itself to be the primary information surface — not a thumbnail that points to a drawer. The drawer becomes secondary detail. You should be able to understand **domain structure, data flow, compliance posture, and system health** purely from the visual grammar of the graph.

This is essentially asking: **can we unify C4, ERD, flow diagrams, and health dashboards into one coherent visual language?**

Let me research the best-in-class references first.Good. Now I have enough. Let me synthesize everything into a proper design plan.

---

## The Design Plan

Here's my full reasoning. This is worth reading carefully because it's a non-trivial problem with real tradeoffs.

---

### The Core Insight You've Identified

You're asking for **visual grammar to replace prose**. The goal is: an expert reading the graph should understand domain structure, data ownership, compliance posture, system health, and module type *without clicking anything*. The sidebar/drawer become confirmations and actions, not sources of primary information.

This is exactly what Dynatrace Smartscape and the C4 model both fail to achieve individually — Smartscape encodes health but not semantics; C4 encodes structure but not health. Neither encodes compliance posture. **Foundry's case is unique because it needs all three simultaneously.**

---

### What the Best-in-Class References Teach Us

**C4 model:** The critical insight is *hierarchical zoom* — not different diagram types, but the same space at different levels of abstraction. Context → Container → Component → Code. Each level answers a different question. The mistake most tools make is flattening these into one undifferentiated soup.

**Dynatrace Smartscape:** Encodes entity type in *shape*, health in *color/glow*, relationship direction in *edge style*. The hover shows a popover with live metrics — not a drawer. The key UX insight: **hover = preview, click = commit**. You don't have to click to assess.

**Datadog Service Map:** Encodes request volume in edge thickness, error rate in node color (green/yellow/red ring). The node itself is a minimal icon — all semantic info comes from the visual frame around it, not inside it.

**Honeycomb BubbleUp:** The key insight is *contextual expansion* — surfaces the most interesting dimension of a node based on what you're investigating, not a fixed layout.

**IBM SevOne / Grafana:** "Summarize and aggregate whilst retaining full context" — meaning you can read the summary at a glance and drill without losing where you are.

---

### The Foundry-Specific Visual Vocabulary

Foundry has exactly **four node types** (Resource, Transfer, Rule, Reactor) and exactly **four dimensions that matter at a glance**:

1. **What is it?** — type + domain (structural)
2. **Is it safe?** — sensitive + compliance posture (regulatory)
3. **Is it healthy?** — test coverage (quality)
4. **Does it have pending state?** — migrations, flags (operational)

The insight is that these four dimensions map cleanly to **four visual channels** that don't require reading text:

| Dimension | Visual Channel |
|---|---|
| Type | **Shape** (distinct geometry per type) |
| Domain | **Cluster background + accent color** |
| Compliance posture | **Border style + ring** (solid = clean, dashed = gap, red ring = sensitive) |
| Test health | **Fill opacity / internal fill gradient** (fully filled = 100%, empty = 0%) |

---

### The Three-Layer Zoom Model

Rather than "hover expands the node," I'd propose something more principled: **three interaction levels** that feel natural, not modal:

**Level 1 — Ambient (no interaction):** The graph at rest. Shape, border, fill encoding. You should be able to answer "what domains exist, which modules have compliance gaps, which are sensitive, which are poorly tested" in 5 seconds without touching anything.

**Level 2 — Hover (cursor proximity):** Node expands ~60% in place, revealing its "richest dimension" — for a Resource: top 3 attributes + compliance req IDs. For a Transfer: its rule chain (the path through rules it enforces). For a Rule: which requirements it covers and the coverage percentage. No click required. Disappears when cursor leaves. This is Dynatrace/Honeycomb's hover popover pattern but integrated *into* the node rather than floating above it.

**Level 3 — Click (commit to focus):** The full detail drawer opens (left side, per ADR-012). The graph dims other nodes. The node's connections highlight. This is the current drawer, now properly secondary.

---

### Edge Encoding

Edges carry enormous semantic information that we're currently wasting. The Foundry domain has distinct relationship types that should be visually distinct:

- **Enforces** (Rule → Resource): dotted amber, arrowhead at resource
- **Calls** (Transfer → Resource): solid blue, directional
- **Triggers** (Resource → Reactor): dashed purple, hollow arrowhead
- **References** (Transfer → Rule): thin solid amber

Edge thickness encodes nothing (we don't have runtime data) but **edge style** encodes relationship semantics.

---

### View Modes (not separate panels — same canvas, different lens)

Instead of Map vs. Compliance as separate tabs, consider **lens modes on the same graph**:

- **Structure lens** (default): domain clusters, type shapes, relationships
- **Compliance lens**: nodes colored by coverage %, gap nodes glow amber, covered nodes fade slightly to let gaps dominate
- **Data flow lens**: animate/highlight the path from Player → to downstream Transfers → to Rules → to Reactors
- **Health lens**: nodes filled by coverage %, border by gap status

These are CSS class swaps, not separate views. The graph doesn't re-render — the visual encoding shifts. This is far more powerful than tabs because spatial memory is preserved.

---

### Node Anatomy (the actual visual design)

Each node type gets a **distinct shape**, not just a color:

```
Resource   → Rounded rectangle (standard box)
Transfer   → Parallelogram (implies movement/flow)
Rule       → Shield/hexagon (implies protection/constraint)  
Reactor    → Rounded diamond (implies transformation/async)
```

Inside each node, three zones:

```
┌─── TYPE STRIPE (3px left border, type color) ──────────────┐
│  [SHAPE ICON]  Name                          [STATUS RING] │
│  ─────────────────────────────────────────────────────────  │
│  [COVERAGE FILL BAR ████████░░ 80%]  [REQ PILLS]           │
│  [INFRA MICRO-BADGES: oban · fsm · ⚠migr]                  │
└────────────────────────────────────────────────────────────┘
```

The **STATUS RING** is the most important innovation: a segmented arc around the top-right corner of the node. Each segment represents one dimension:
- Segment 1 (top): compliance (green = covered, amber = gap, red = missing)
- Segment 2 (right): test coverage (green/yellow/red based on %)
- Segment 3 (bottom-right): operational (blue = pending migration, gray = clear)

This is borrowed from health ring designs (Apple Watch Activity rings, Dynatrace status rings). It encodes 3 independent dimensions in a single compact visual.

---

### What I'll Build

A **v3 prototype** that demonstrates:

1. **Distinct node shapes** via SVG path per type (not just color)
2. **Status rings** on each node (3-segment arcs)
3. **Coverage fill** — the node interior fills proportionally
4. **Hover expansion** — node expands in-place showing type-specific preview content (no click required)
5. **Edge type encoding** — 4 relationship styles
6. **Lens mode switcher** — same graph, 3 visual lenses (Structure / Compliance / Health)
7. **Animated data flow** — highlight the path from a selected node through its dependency chain

The drawer remains for commit-level detail. The hover handles peek-level. The graph itself handles ambient-level. Three distinct layers of information density, each triggered by increasing commitment from the user.

---

## The Real Answer

Your question has two parts that need to be separated before combining them.

### Part 1: Can you unify C4, ERD, flow diagrams, health dashboards, user scenarios, and forms in one space?

**Technically: yes. Practically: it depends entirely on whether the audiences and cognitive tasks overlap.**

The reason these diagram types exist separately isn't arbitrary — each was designed for a specific cognitive task performed by a specific audience:

| Diagram | Cognitive task | Primary audience |
|---|---|---|
| C4 (Context/Container) | "What exists and how does it connect" | Architects, new engineers |
| ERD | "What data is stored and how it relates" | Data engineers, DBAs |
| Sequence/Flow | "What happens in what order when X occurs" | Developers, QA |
| Health dashboard | "Is the system working right now" | DevOps, on-call |
| EventStorming | "What are the business events and who triggers them" | Domain experts, product |
| User scenario/journey | "What does the user experience" | Product, UX, compliance |
| Form spec | "What does the user input and what are the rules" | Dev, UX, QA |

These are genuinely different questions. Forcing all of them onto one canvas at once creates a diagram that answers none of them well — this is the classic mistake of the "enterprise architecture wall" that nobody actually reads.

**The C4 model's key insight, which is still the right answer:** a single *model* (the data), many *views* (the renderings). You don't unify the diagrams — you unify the underlying model, then render it differently depending on the question being asked. A modelling tool builds up a non-visual model of your software architecture, a single definition of all elements and relationships, and creates different views (that become diagrams) on top of that model.

This is exactly what Foundry already is — `mix foundry.context` is the unified model. The Studio is the view layer.

---

### Part 2: What does Foundry specifically need that existing tools don't cover?

Let's be honest about the gap inventory. Here's what the existing landscape covers and doesn't:

**Well-covered by existing tools:**
- C4 structural maps: IcePanel, Structurizr
- ERD / schema view: any database tool, Prisma Studio
- Event flow / sequence: Mermaid, PlantUML, EventCatalog
- Health dashboards: Datadog, Dynatrace, Grafana
- User journey maps: Miro, FigJam
- Compliance matrices: spreadsheets, GRC tools

**What Foundry's context makes uniquely possible — and what nothing else does:**
- Showing **structural, compliance, and test health simultaneously** on the same module
- Connecting **a business rule (Rule module) directly to the regulatory text it implements** (RG-UK-031 → `ResponsibleGamingCheck`)
- Showing **what would change** if you proposed a modification — impact on compliance coverage, test coverage, and downstream modules — before the change is made
- The **Ash/Phoenix DSL introspection** producing a live, always-current view that static diagrams can never achieve

---

### Part 3: What have we forgotten?

This is the most important question. Let me inventory the view types that genuinely matter for Foundry's users and cross them against what we've designed so far:

**1. Structural view** ✓ (System Map)
What modules exist, what domain they're in, how they connect.

**2. Compliance coverage view** ✓ (Compliance panel)
Which regulatory requirements are covered, which have gaps.

**3. Data flow view** ✗ *not designed*
How data moves through the system when a specific user action occurs. E.g. "when a player withdraws, trace the path: Player → WithdrawalTransfer → KycCheck → ResponsibleGamingCheck → Wallet → LedgerEntry." This is the most useful view for onboarding engineers and for compliance auditors tracing an action.

**4. Sensitive data view** ✗ *not designed*
Which fields across the system are PII, monetary, or sensitive. Where does player email appear? Which tables have `paper_trail`? Which don't and should? This is a compliance audit view.

**5. Test coverage topology** ✗ *not designed*
Not just per-node percentages but the actual testing graph: which modules have full property+scenario+e2e, which are partially covered, which have zero. Gaps are obvious at a glance.

**6. Dependency / impact view** ✗ *partially*
If I change `Wallet`, what else breaks? Which modules import it, which tests reference it, which compliance requirements run through it? This is the impact analysis view — currently buried in the review panel, but valuable without a proposal context too.

**7. User scenario view** — *your question* — this is the interesting one.

In Foundry's domain (iGaming, fintech), a "user scenario" means: a player tries to withdraw £500. What path does that traverse? What rules fire? What can fail? This is not a user journey map (UX tool) — it's a **compliance scenario trace**. "Show me the execution path of this action, which rules it invokes, which regulatory requirements those rules cover, and where the test gaps are on that path."

This is genuinely unique to Foundry and genuinely valuable. It's like a sequence diagram but sourced from the live DSL model rather than hand-drawn. EventStorming does something similar in workshops but it's a discovery tool, not an always-live system view.

**8. Schema / ERD view** — *partial need*
For Resources, showing the actual attribute structure with types, relationships, and FK connections. This is a narrower view than the full map. Useful for data engineers and compliance auditors who need to understand exactly what data is stored.

**9. Operations timeline / audit view** — *Phase 6 concern*
Runbook health, proposal history, applied changes over time. A timeline rather than a graph.

**10. Regulatory jurisdiction view** — *possibly unique*
Which domains/modules apply in which jurisdictions (UK, MGA, etc.)? For a multi-jurisdiction iGaming platform this is actually critical for a compliance officer.

---

### The Honest Scoping Answer

Trying to put all 10 of these into one canvas simultaneously would create exactly the "enterprise architecture wall" problem. The C4 FAQ is explicit about this: it's tempting to try and include the entire story on a single diagram — but if nobody understands the diagram, nobody is going to look at it.

**The right architecture is:**

One **unified model** (what `mix foundry.context` already produces) rendered through **named views**, each answering one question, all accessible from the same canvas via a view-switcher. Not separate panels — same spatial canvas, different visual encoding + different nodes surfaced.

The views that make sense for Foundry specifically, ordered by value:

1. **Structure** — what exists (current System Map)
2. **Compliance coverage** — what's covered vs gapped (current Compliance panel, but as a map lens not a separate panel)
3. **Scenario trace** — "trace this user action through the system" — *new, high value*
4. **Sensitive data** — where is PII/financial data and what protects it — *new, compliance-critical*
5. **Test topology** — coverage gaps as a graph problem — *new*
6. **Impact** — what does this module touch — *new, available on demand from any node*

**For user scenarios and forms specifically:** these belong as a **scenario trace view** — not a UX journey map, but a compliance execution trace. "Player withdraws → show the full path, which rules fire, which reqs they cover, where the test gaps are." This is unique to Foundry and doesn't exist anywhere else.

---

### What This Means for the Design

The practical conclusion is this: don't try to build one diagram that shows everything. Build a **lens system** on a single canvas:

- The canvas is always the same spatial graph
- Switching lenses changes what's encoded visually (colors, highlights, which edges are shown)
- The scenario trace is a special mode: you pick a starting module + an action, and the graph animates the path through the system, highlighting which nodes are involved and surfacing coverage gaps on that specific path

This is achievable, genuinely novel, and directly serves the compliance audit use case that is Foundry's core value proposition. Nothing in IcePanel, Structurizr, Dynatrace, or any ERD/C4 tool does this.