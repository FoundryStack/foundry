# FOUNDRY — COMPLETE LANDING COPY

---

## HERO

**Your domain model and your running system.**
**Finally the same thing.**

Foundry is a complete platform for building complex domain systems — where declarative specifications are the executable code, every layer is always visualizable, and an AI agent understands your entire architecture before it changes a single line.

**[ Book a demo → ]**

---

## SECTION 1 — The problem nobody talks about honestly

**Starting is no longer the hard part.**

An AI coding tool can scaffold a working application in an afternoon. The first demo runs. The database schema looks reasonable. The API responds. Everyone is optimistic.

Then the system grows.

Six months in, the original engineer is the only person who can explain why a particular pattern was chosen. The architecture document in Confluence describes a system that no longer exists. New engineers take weeks to become productive — not because the codebase is large, but because it is opaque. The AI tools that helped you start now hallucinate changes into a system they cannot fully see. They append instead of refactor. They solve the local problem while silently breaking something three layers away.

Google's 2025 DORA report put numbers to what every senior engineer already knows: a 90% increase in AI tool adoption correlated with a 9% rise in bug rates and a 91% increase in code review time. GitClear found that AI-assisted code churn doubled — not because the tools are careless, but because they operate without context. They write into a system they have never seen whole.

This is not a tooling problem. It is a structural one. Imperative code accumulates opacity. The larger it gets, the harder it becomes for any person — or any agent — to hold the entire system in mind.

And the standard answer — more tools, better documentation, stricter conventions — makes it worse. Every disconnected service, every separate SaaS, every additional integration is more context that falls outside what the AI can see. The system fragments. The agent guesses. The team pays.

---

## SECTION 2 — The structural answer

**Most systems exist in three versions simultaneously.**

There is the system as it was designed — living in architecture documents, decision records, someone's memory from two years ago. There is the system as it was built — imperative, accumulated, shaped by a hundred pragmatic decisions that never made it into any document. And there is the system as anyone currently understands it — which is usually a partial, personal, and quietly incorrect mental model held by whoever has been on the project longest.

These three versions diverge from day one. Silently. Continuously. Until something breaks in a way nobody can explain, or until the person who holds the mental model leaves.

Foundry makes these three versions the same thing — permanently, by construction, not by discipline.

Your domain is declared once in a clean, readable DSL. Resources, actions, relationships, policies — the full shape of your business logic, expressed in the simplest possible terms. That declaration is not documentation sitting alongside code. It is the running code. It is what the system map renders. It is what the AI agent reads before proposing any change. When the model changes, the system changes. When the system changes, the visualization changes. There is no synchronization problem because there is no separation.

This is what Executable Model-Driven Engineering means in practice. Not a diagram that approximates the system. Not documentation that describes it. A single source of truth that generates, validates, and visualizes the running application — and stays honest about what it contains.

---

## SECTION 3 — The foundation

**The infrastructure decision you will never have to make.**

The BEAM was originally developed by Ericsson in the 1980s to handle the massive demands of telecom switches — systems that needed to run without failure for years while handling millions of concurrent connections. That requirement shaped every design decision in the runtime. Lightweight processes — not OS threads. Preemptive scheduling across every CPU core. Fault isolation so complete that one crashing process cannot affect its neighbors. Message passing instead of shared state.

The results, in production, are concrete:

The Phoenix framework maintained 2 million active WebSocket connections on a single server — one EC2 instance, 2ms average latency, no crashes, no GC pauses, roughly 1KB of memory per connection. The equivalent in Node.js requires a load balancer, multiple instances, Redis for pub/sub, and a separate WebSocket service. The BEAM handles all of it natively.

Pinterest migrated one system from 200 Python servers to 4 Elixir nodes, saving over $2 million per year. Bleacher Report reduced infrastructure from 150 servers to 5. One engineering team replaced an AWS Lambda stack costing $16,000 per month with three Elixir nodes costing $150 — handling 12 million requests per hour with sub-second latency.

These are not benchmarks. They are infrastructure bills.

The reason is structural, not magical. Traditional stacks reach for external services — a message queue, a pub/sub layer, a caching tier, a background job processor — because the runtime cannot handle these concerns natively. Each external service is an integration to maintain, a failure mode to handle, a cost to pay. The BEAM handles all of it inside the same runtime. Fewer moving parts means less to break, less to operate, and a fraction of the infrastructure cost.

Foundry gives you this foundation without the months of evaluation, integration, and tuning that would otherwise precede it. The stack is chosen, integrated, and production-ready from the first line you write.

---

## SECTION 4 — The AI agent that actually works

**The reason most AI coding agents degrade as systems grow is not model quality. It is context.**

A typical agent sees the file you are working on. It might see adjacent files. It does not see the architectural decision from eight months ago that shaped the current pattern. It does not know which resources are sensitive. It does not know what invariants the system must maintain. It guesses at the structure of a system it has never seen whole — and its guesses get worse as the system gets larger and the codebase gets more fragmented.

Foundry's agent works differently — not because of a better model, but because of what it has access to before it proposes anything.

It reads your domain model: every resource, every action, every relationship, every policy, live from the running code. It reads your architectural decisions — the ADRs you wrote that explain not just what the system does but why specific choices were made. It reads your invariants, your compliance requirements, your existing patterns. It finds what already exists before proposing something new. It knows what is sensitive and what requires human approval before it generates a single line.

Then it proposes. You see the diff, the affected resources on the system map, the invariants checked. You decide.

This is the distinction from vibe coding. The agent operates against a gold standard — your own declared architecture — and the system validates every proposal before it reaches you. It is not autonomous. It is collaborative, with full context, bounded by rules you defined. Forrester estimates three out of four teams that attempt to build agentic architectures on disconnected tooling will fail. The context is too fragmented, the systems too opaque. Foundry is the environment where agentic development holds together.

---

## SECTION 5 — From domain model to running system

**One coherent system. Every layer.**

A Foundry platform is not a backend with a frontend bolted on. It is a single coherent system, declared at the domain level and rendered at every layer from that declaration.

You model your domain. Ash resources define your entities, actions, and policies — clean, immediately readable by any engineer on day one. From that model, Phoenix LiveView renders real-time interfaces. Forms, tables, dashboards, live updates — built from the same declarative foundation. When the domain changes, the UI stays in sync. Not because of a code generation step you have to remember to run. Because they share the same source.

Testing is structured, not retrofitted. Every resource generates a test skeleton. Compliance requirements drive end-to-end scenarios. Unit tests, property-based tests, mutation tests, integration tests — all derived from the model, all aware of what the system is supposed to do.

Multi-agent business processes follow the same principle. Complex workflows — approvals, escalations, parallel branches, exception handling, human gates — declared as deterministic Reactor workflows. The agent can propose new steps. The human approves them. The system map shows every step, every state, every dependency. Three years later, a new engineer can read the entire process without asking anyone.

The system map is not a diagram someone drew once. It is a live, interactive graph generated from the running code — every domain, every resource, every relationship, every linked architectural decision. Always current. Always accurate. Readable by a new engineer on day one, or an auditor who has never seen the codebase.

---

## SECTION 6 — What you can build

**Any domain where complexity is the real problem.**

Foundry is not purpose-built for one industry or one type of application. It is built for the class of problem where the domain is complex, the system has to be correct, and it has to be understood and evolved by different people over years.

**IT Operations** — ITSM, ITAM, ESM. Incident management, change management, asset lifecycle, service catalogs, cross-department onboarding workflows. Every ITIL process is a state machine on a domain model. Foundry declares it correctly once, visualizes it completely, and evolves it without an admin console or a certified consultant. The same platform that runs IT operations for a 50-person company runs it for a 5,000-person enterprise — because the model scales with the domain, not with a pricing tier.

**Software Delivery** — SDLC platforms, DevOps orchestration, release management, test governance. Requirements, design, implementation, review, deployment as a unified domain. Not Jira plus GitHub plus Confluence plus five more integrations. One coherent model where the copilot can trace a business requirement to a running feature without losing context.

**Financial Systems** — Payment ledgers, wallets, transaction processing, regulatory reporting. Money requires correctness above everything. Sensitive resources with compiler-enforced invariants, full audit trail, dual-approval on every critical change. The system that handles 40,000 transactions per hour runs on three nodes. The engineer maintaining it understands every resource completely.

**Real-time Operations** — iGaming backends, trading platforms, live logistics, IoT event processing. Phoenix handles millions of WebSocket connections on a single commodity server. Player wallets, real-time odds, game state, regulatory events per jurisdiction — all in one domain model, running on infrastructure that costs a fraction of what a microservices equivalent would require.

**Healthcare and Clinical Systems** — Patient flows, care coordination, clinical decision support, scheduling. Human-in-the-loop gates on decisions that cannot be autonomous. Complete audit trail. A system map that a compliance officer can read without a technical guide.

**Business Process Platforms** — Order orchestration, supply chain, HR operations, legal case management, insurance policy administration. Complex long-running processes with approvals, exceptions, parallel branches, and SLA tracking — declared as Reactor workflows, visualizable at every step, evolvable by the copilot without breaking what already runs.

**Enterprise Internal Platforms** — The most underserved category in software. Every large organization is running internal tools built badly, maintained expensively, understood only by the engineers who first wrote them. Foundry is the answer that did not exist until now.

---

## SECTION 7 — What it is not

**Not a black box. Not a lock-in. Not a configuration layer.**

Every Foundry project compiles to a standard Elixir application. The DSL generates real, inspectable, production-grade code. You can read it, modify it, and run it entirely without Foundry. The platform is a layer of tooling, visualization, and intelligence over an architecture you own outright.

Foundry is also not a product you configure to approximate your domain. You declare your domain exactly as it is. If your business logic does not fit a predefined schema, that is not a constraint you work around — it is a domain you model correctly.

And it is not autonomous. The agent proposes. The system validates. You decide. Every change is classified, every sensitive change requires approval, every decision is traceable. The speed of agentic automation, bounded by the safety of declared architecture.

---

## SECTION 8 — How to work with Foundry

**Three ways, depending on where you are.**

**Design Partner** — For teams building serious domain systems who want to shape the product alongside us. You get early access, direct roadmap influence, and a Foundry team that works with you on your actual architecture. In return, we get the real-world feedback that makes the platform what it should be. Five to ten partners initially. This is a structured relationship, not a beta signup.

**Sponsored Domain Build** — For organizations with a specific domain problem and a willingness to build it publicly as a reference implementation. Foundry builds alongside your team. You get a production-grade foundation at a fraction of the cost of building it alone. The result becomes a public domain template — a case study that demonstrates what Foundry does at its best, and a starting point for every team that faces the same domain after you.

**Cloud Hosted** — For smaller teams or teams that want zero infrastructure overhead. Foundry hosts the environment, the system map, the copilot, the CI integration. You own the domain model and the application code entirely. Deploy to our infrastructure or eject to your own at any point — it is a standard Elixir application either way.

---

## SECTION 9 — Where we are

**Pre-launch. Honest about it.**

The structured data layer is complete. The system map runs live against real codebases. Domain introspection via Mix tasks is stable and in use. The copilot answers questions about your domain accurately — reads your resources, your ADRs, your invariants — before proposing anything.

Code change proposals are in active development. Full-stack scaffolding, multi-agent workflow tooling, and the hosted cloud service follow in phases.

There are no published case studies yet. The design partner program exists to build them — together, on real systems, with teams who already feel the problem Foundry solves.

**What design partners get today:** the system map, domain introspection, copilot Q&A on their codebase, direct access to the team, and a seat at the table for every product decision that follows.

---

## SECTION 10 — The ask

**We are looking for teams who have already felt the complexity wall.**

Fintech teams rebuilding a ledger system for the third time. iGaming platforms that have outgrown their original architecture. Healthcare organizations running clinical workflows in spreadsheets and Slack. Enterprise teams about to commission an internal platform for the second time. Organizations paying six figures per year for ESM or ITSM software that almost fits their actual process.

If you are building something complex, domain-heavy, and long-lived — and you want to build it in a way that your team, your AI, and your auditors can all understand three years from now — we should talk.

**[ Book a demo → ]**     **[ Read the technical overview → ]**




===

Good. Let me think through all of this systematically.

---

## Demo domains — what to show and why each one

The domains need to cover different *classes* of problems, not just different industries. Each demo should make a different architectural point.

**1. Fintech — Payment Ledger**
The classic hard problem: money must never be wrong, never be lost, always be auditable. Shows Foundry's strength in invariant enforcement, dual-approval workflows, paper trail on every sensitive resource. The domain is small — 6-8 resources — but the constraints are extreme. Perfect for showing how declarative + compiler-enforced rules replace an entire category of defensive code.

**2. iGaming — Real-time Back Office**
High concurrency, real-time odds and wallet updates, regulatory compliance per jurisdiction, fraud detection agents running continuously. This is the BEAM showcase — the case where 50,000 concurrent players on a single node is not a benchmark but a cost structure. Shows multi-agent workflows, real-time LiveView UI, and compliance-linked invariants in one domain.

**3. Healthcare — Patient Flow Platform**
The human-in-the-loop showcase. Clinical decisions cannot be autonomous. Shows Reactor workflows with mandatory human gates, sensitivity classification, audit trails, and how the system map makes a complex multi-step process readable to non-engineers — including regulators. Also shows Foundry's value to compliance officers who need to understand what the system does without reading code.

**4. Marketplace / Logistics — Order Orchestration**
The business process showcase. Complex state machines — order placed, inventory checked, payment captured, fulfillment triggered, exception handled. Multi-agent coordination. Shows how deterministic Reactor workflows replace what most teams build as a spaghetti of background jobs, webhooks, and manual retries. The before/after is visually dramatic on the system map.

**5. Internal Enterprise Platform — HR or Finance Operations**
The "not SaaS" case. A large company building internal tooling — approvals, reporting, data pipelines, integrations with legacy systems. Shows that Foundry is not just for startups. The key insight here: internal platforms are the most underserved category, the most likely to be built badly, and the ones where "code you can always understand" matters most because the original team is usually long gone.

---

## Cooperation, sponsorship, and growth tiers

This is actually a business model question as much as a positioning one. Let me think through what makes sense at each level.

**Design Partner Program** — for teams building something serious who want to shape the product. Not free. Not full price. A structured relationship: early access, direct roadmap influence, Foundry team involvement in their architecture. Maybe 5-10 partners initially. The value exchange is explicit: they get a head start, you get real-world validation.

**Sponsored Domains** — Foundry builds a reference implementation of their domain, together, as a showcase. The sponsor gets a production-grade foundation. Foundry gets a public case study and a proven domain template others can start from. This is particularly powerful for the demo library — every sponsored domain becomes a template in the platform.

**Cloud / Hosted Service** — the path for smaller teams or teams that want zero infrastructure ownership. Foundry hosts the environment, the CI, the system map, the copilot. The customer owns the domain model and the application code. This is the SaaS tier — monthly subscription, scales with team size or resource count. Key differentiator from self-hosted: the eject story still applies. You can always take your standard Elixir app and run it yourself.

**Self-hosted / Enterprise** — for larger organizations, regulated industries, teams that cannot send code to an external service. Full Foundry environment runs in their infrastructure. License model. Includes the compliance and audit features more prominently.

**Open core** — worth considering. The independent packages — `spark_meta`, `spark_lint`, `reactor_human_gate` — are already designed to be reusable outside Foundry. Publishing these openly builds community, attracts Elixir ecosystem contributors, and creates a funnel of developers who discover Foundry through the primitives. The platform itself stays commercial.

---

## The roadmap — honest version

Based purely on what the docs describe as phased:

**Now — Phase 1-2 (Foundation)**
Structured data layer complete. System map viewer working. Live domain introspection via Mix tasks. CI integration. This is demonstrable. This is what design partners get today.

**Near — Phase 3 (Copilot, questions only)**
The AI agent answers questions about the domain accurately. No code changes yet. This is the trust-building phase — the team learns what the agent knows before it can touch anything. Realistic: 2-3 months.

**Next — Phase 4-5 (Copilot proposes changes)**
The agent generates diffs. Change classification active. Human approval required. The proposal lifecycle — draft, review, approve, apply — fully working. This is where Foundry becomes genuinely useful for day-to-day development. 4-6 months.

**Later — Phase 6-7 (Full stack + agents)**
LiveView scaffolding, form and UI generation, multi-agent Reactor workflows, end-to-end test generation. The complete picture. 8-12 months.

**Future — Phase 8+ (Cloud service, domain templates, marketplace)**
Hosted cloud tier. Sponsored domain library publicly accessible. Community template marketplace. Agent step marketplace — reusable business process components teams can compose.

---

## What else belongs on the landing

A few things that naturally fall out of this thinking:

**A template library preview** — even showing three domain templates as cards (Payment Ledger, iGaming Back Office, Patient Flow) signals that you're not starting from zero. The reader thinks "I could have this running by end of week" rather than "this sounds interesting but I don't know where to start."

**The ecosystem signal** — Foundry sits on top of a genuinely strong open source ecosystem. Ash Framework has real adoption. Phoenix LiveView is proven. Reactor is mature. Naming the ecosystem — not as a technology list but as a community — signals that this is not a dead-end bet. The reader is not betting on Foundry alone, they're betting on an ecosystem with momentum.

**The team / why us section** — for a pre-launch product asking for trust, "who built this and why" matters enormously. Not a bio page. A short paragraph about what problem the team actually lived through that made Foundry necessary. The most credible origin story is always a real one.

**A reading path for the skeptical architect** — something between "I'm curious" and "book a call." A technical deep-dive document, a real domain walkthrough, a short video. Something that lets someone spend 20 minutes going deeper without committing to a human conversation.

---

## How I see the full landing structure now

```
HERO
"Your domain model and your running system. Finally the same thing."

↓ THE PROBLEM
Starting is easy. Surviving scale is not.
[Before/after: fragmented stack vs Foundry domain graph]

↓ THE STRUCTURAL ANSWER
One declarative model. Executable. Visualizable. Always current.
[Live interactive system map — real domain]

↓ THE RUNTIME
The infrastructure decision you'll never have to make.
[Cost comparison: BEAM vs traditional — interactive]
[Pinterest / Discord / $16k→$150 stories]

↓ THE AI AGENT
Proposes with full context. You decide.
[Agent interaction mockup — diff + system map]
[Code snippet: one readable Ash resource]

↓ FULL STACK
From domain model to production UI.
[Layer diagram: model → API → LiveView → tests]

↓ DEMO DOMAINS
Five reference domains. Pick yours.
[Cards: Fintech / iGaming / Healthcare / Logistics / Enterprise]

↓ HOW TO WORK WITH US
Three paths — Design partner / Sponsored build / Cloud hosted
[Tier cards with clear value exchange]

↓ ROADMAP
Honest. Phased. Where we are today.
[Timeline: Now / Near / Next / Later]

↓ THE ASK
For teams building domain-heavy systems who have already felt the wall.
[Book a call →] [Read the technical deep-dive →]
```

===

## Three open questions worth settling

**1. The demo domains — how live do they need to be?**

There's a spectrum here:

- **Static cards** — name, description, a screenshot. Lowest effort, least impressive.
- **Interactive system map** — the actual domain graph, explorable in the browser. No code running, just the visualization. This is the sweet spot — shows the core product claim without requiring a full backend.
- **Live sandbox** — a real Foundry environment for each domain, accessible immediately. Most impressive, significant engineering investment.

For a pre-launch landing, the interactive system map is the right call. It shows the thing that matters most — that the model is always visualizable — without overpromising what the product can do today.

**2. The cooperation tiers — what's the actual ask at each level?**

Right now we have three tiers sketched:
- Design partner — structured relationship, shaped roadmap
- Sponsored build — Foundry builds with you, you become a case study
- Cloud hosted — self-serve, smaller teams

But what does someone *do* on the page for each tier? All three currently end at "book a call" which collapses a meaningful distinction. The sponsored build and cloud tiers should have different CTAs — maybe an expression of interest form for sponsored builds, and a waitlist or early access signup for cloud. The design partner path stays as a call because that relationship needs a conversation.

**3. The roadmap — public or gated?**

Showing a roadmap publicly on a pre-launch landing is a double-edged decision. It signals confidence and transparency — which builds trust. But it also invites competitors to see exactly where you're going, and it creates expectations you're accountable to.

The middle path: show the *phases* and their logic publicly, but keep specific features and timelines for design partners only. "Here is how we think about building this" rather than "here is what ships in Q3."

---

## One thing nobody has said yet

The landing currently has no social proof at all — which is expected for pre-launch, but worth addressing directly rather than ignoring.

The honest move: name the absence. Something like a short line in the design partner section: *"We are pre-launch. There are no case studies yet. The design partner program exists to build them together."* That kind of transparency from a technical product actually builds more trust than a page of invented testimonials. The reader is a senior engineer or CTO. They respect honesty over polish.

---

## What I think we should decide right now