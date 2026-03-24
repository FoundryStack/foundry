# ADR-021 — Delivery Model: Design Partner, Sponsored Build, Cloud Hosted

**Status:** Accepted
**Date:** 2026-03-23
**Supersedes:** —
**Tags:** delivery, cloud, saas, design-partner, sponsored-build, multi-tenancy

---

## Context

Foundry has three distinct delivery modes for early customers. Each mode has a
different relationship structure, a different cost model, and — critically — different
implications for the Foundry codebase itself. The cloud hosted tier in particular
introduces multi-tenancy requirements that do not exist in the local
(`mix foundry.studio`) or single-repo cloud-connected modes described in
AGENTS.md §What This System Is.

This ADR records the three delivery modes, their boundaries, and the codebase
consequences of each.

---

## Decision

### Mode 1: Design Partner

**Relationship:** Structured engagement. Not a beta signup. Foundry team works
directly with the partner on their actual domain architecture.

**Access:** Full Foundry environment — local mode, cloud mode, system map, copilot
(phase-gated per BUILD_SEQUENCE.md), direct Slack/call access to core team.

**Cost model:** Not free. Not full price. A fixed engagement fee covering the
partnership duration, agreed before onboarding. Partners are not investors and hold
no equity. They hold roadmap influence proportional to the specificity and
actionability of their feedback.

**Selection criteria:**
- Building a domain-heavy system in one of the target categories (ADR-018)
- Has an existing Elixir/Ash codebase OR is greenfield and committed to the stack
- Has at least one senior engineer who can evaluate technical decisions critically
- Is willing to provide structured feedback and participate in monthly review calls
- Is comfortable with the product being pre-production in some phases

**Codebase implications:**
- No new infrastructure required. Design partners use existing local or
  cloud-connected modes (AGENTS.md §What This System Is).
- Partner AGENTS.md files and spec-kits are maintained by the partner, not by Foundry.
- Foundry may contribute ADR drafts or spec-kit scaffolding as part of the engagement.
- Design partner domains are candidates for the reference implementation library
  (ADR-018 §For the demo domain library) only with explicit written consent.

**Capacity:** 5–10 partners maximum in the initial cohort. Intake is sequential,
not simultaneous — each partner is onboarded only after the previous engagement
is stable.

---

### Mode 2: Sponsored Domain Build

**Relationship:** Project engagement. Foundry builds a reference implementation of
the sponsor's domain alongside their team. The result is open — a public domain
template in the Foundry library.

**Access:** Same as design partner, plus active co-development from the Foundry team
on the domain model, ADRs, and spec-kit.

**Cost model:** Sponsor funds the build. In exchange:
1. They receive a production-grade Foundry domain implementation at a fraction of
   the cost of building it alone.
2. The result is published as a Foundry reference domain — fully open, with the
   sponsor credited.
3. The sponsor becomes the canonical case study for that domain category.

**What is and is not open-sourced:**
- The domain model, ADRs, spec-kit, and Foundry configuration: open.
- The sponsor's proprietary business logic, customer data, and production
  infrastructure: never included, never open-sourced.
- The Foundry platform itself: not open-sourced as part of this arrangement.

**Codebase implications:**
- Each sponsored domain becomes a subdirectory in `foundry/reference_domains/`.
- Reference domains are valid Foundry target platforms: they have their own
  AGENTS.md, ADRs, regulations, and spec-kit index.
- The reference domain CI runs `mix foundry.lint.all` and
  `mix foundry.diagram.generate` as part of Foundry's own CI — sponsored domains
  are regression tests for the platform.
- Reference domains ship as templates in the Foundry template library (Phase 5+).
  Template selection via `mix foundry.new --template <domain>` installs the
  reference domain's Ash resources, ADRs, and spec-kit as a starting point.

**Capacity:** 2–3 sponsored builds per quarter. Each requires core team bandwidth.

---

### Mode 3: Cloud Hosted (SaaS tier)

**Relationship:** Self-serve. Smaller teams or teams that want zero infrastructure
overhead. Foundry hosts the environment; the customer owns the domain model and
application code entirely.

**Access:** Foundry Studio UI, system map, domain introspection, copilot
(phase-gated), CI integration, hosted deployment target. No direct team access —
support via documentation and async channels.

**Cost model:** Monthly subscription. Tiered by team size or active resource count
(to be defined in a separate pricing ADR when the cloud tier enters active
development). The hosted deployment target is a separate line item from the
Foundry environment itself.

**No lock-in — by construction, not by a task:**
A Foundry-hosted customer project is a standard Elixir/Ash/Phoenix application.
Foundry is a tooling and environment layer — it does not wrap or modify the
application code itself. There is nothing to eject from. The customer can clone
their repository, point it at their own infrastructure, and run it without Foundry
present. The application has no runtime dependency on Foundry. This is a structural
property of how Foundry works (tooling layer over a standard Elixir app), not a
feature that requires implementation.

The git-backed storage model (ADR-015) reinforces this: all proposal files, ADRs,
spec-kit documents, and configuration live in the customer's own git repository.
Foundry holds no customer data in a proprietary store that would require export.

---

### Multi-tenancy model for the cloud tier

The cloud tier hosts multiple customer environments on shared Foundry infrastructure.
This requires tenant isolation at both the application data layer and the Foundry
metadata layer.

**Foundry metadata isolation (proposals, spec-kit, audit log):**
Per ADR-015, Foundry's own storage is git-backed files + ETS only. In the cloud
tier, each customer environment connects to their own git repository. ETS tables
are namespaced per customer session — Foundry holds no cross-customer shared mutable
state. A customer environment failure does not affect other customers.

**Application data isolation (customer's Ash resources):**
Foundry's cloud tier uses Ash's native multitenancy support, which provides two
documented strategies:

**Strategy 1: `:attribute` multitenancy**
The simplest approach. A `tenant_id` (or equivalent) attribute is declared on every
multitenant resource. Ash enforces that all queries specify a tenant — a query
without a tenant raises an error rather than returning cross-tenant data. This
approach works for any Ash data layer and requires minimal migration overhead.

```elixir
multitenancy do
  strategy :attribute
  attribute :organization_id
end
```

Suitable for: lower isolation requirements, simple data models, early-stage
customers on the cloud tier who have not yet committed to a schema strategy.

**Strategy 2: `:context` multitenancy via AshPostgres PostgreSQL schemas**
Each tenant organisation gets a dedicated PostgreSQL schema (e.g. `org_10`).
Tenant migrations are tracked separately from public schema migrations in
`priv/repo/tenant_migrations`. When a new customer environment is provisioned,
AshPostgres creates the schema and runs tenant migrations automatically via the
`manage_tenant` configuration on the Organisation resource.

```elixir
# Organisation resource (the tenant)
postgres do
  table "organizations"
  repo MyApp.Repo
  manage_tenant do
    template ["org_", :id]
    create? true
    update? false
  end
end

# Any multitenant resource
multitenancy do
  strategy :context
end
```

Suitable for: stronger data isolation requirements, regulated industries (fintech,
healthcare), customers who need per-tenant data deletion guarantees, customers
migrating from dedicated-database setups.

**Default strategy for the cloud tier:** `:context` (PostgreSQL schema-based).
Rationale: the target customers for the cloud tier — teams in regulated domains —
have data isolation requirements that make schema-per-tenant the correct default.
The performance advantage (each tenant's queries run against smaller dedicated
tables rather than a shared large table) also aligns with the platform's
infrastructure cost positioning. Customers who need a simpler setup can request
`:attribute` strategy during onboarding.

**LLM API keys in the cloud tier:**
Two options, both supported:
1. Customer provides their own Anthropic API key — stored encrypted per customer,
   used only for their copilot sessions, never logged with prompt content.
2. Foundry provides pooled API access — metered, included in the subscription
   tier, subject to the same prompt content guarantees.

LLM prompt content is never logged in either case (ADR-015 §Proposal File Format).

---

### What is NOT in the cloud tier at launch

- Multi-region deployment
- SSO / SAML (planned, not v1)
- Custom domain for the Studio UI (planned, not v1)
- SLA guarantees beyond best-effort uptime
- Hosted deployment target for the customer's application (Foundry environment
  only at launch; hosted deployment of the customer's Elixir app is a subsequent
  phase)

---

## Consequences

### New module: `Foundry.Cloud.TenantProvisioner`

Handles lifecycle management of customer environments in the cloud tier:
- Provisioning a new customer environment: creates the PostgreSQL schema, runs
  tenant migrations, registers the customer's git remote
- Suspending/resuming environments on account changes
- Deprovisioning: schema removal (with export confirmation step) on cancellation

This module is cloud-tier-only. Local mode (`mix foundry.studio`) has no concept
of tenants and must not depend on this module.

### Tenant migrations in the cloud tier

AshPostgres schema-based multitenancy requires tenant migrations to be tracked
separately in `priv/repo/tenant_migrations`. In the cloud tier, when Foundry
deploys updates that affect the Foundry Studio application's own data layer
(not the customer's application), tenant migrations must be run against all
active customer schemas. `Foundry.Cloud.TenantProvisioner` is responsible for
running `mix ash.migrate --tenant-migrations` across all active tenants on
deployment.

### Storage model (ADR-015 addendum)

ADR-015 records git-backed files + ETS only for Foundry's own storage. The cloud
tier adds one constraint: git remotes are per-customer repositories, authenticated
via per-customer credentials stored in a secrets manager external to Foundry's
own storage model. Credential storage is an infrastructure concern managed by
the cloud tier's deployment configuration, not by Foundry application code.

### Pricing ADR deferred

Specific pricing tiers and resource-count thresholds are deferred to a separate
ADR when the cloud tier enters active development. This ADR records only the
structural commitments — isolation model, no-lock-in guarantee, multi-tenancy
strategy — that have codebase consequences now.

---

## Alternatives considered

**Custom OTP supervision tree per customer for isolation.**
Rejected. Ash's native multitenancy (`:context` strategy with PostgreSQL schemas)
provides the correct isolation layer at the data level, which is where cross-tenant
contamination is actually a risk. BEAM process isolation between customer sessions
is a property of how Phoenix LiveView sessions work, not something that requires
a custom supervisor. Inventing a `TenantSupervisor` abstraction on top of what
Ash and Phoenix already provide would add complexity without adding isolation.

**`:attribute` strategy as the default.**
Rejected as default, supported as option. Schema-based isolation is the correct
default for the target customer profile (regulated industries, domain-heavy systems).
`:attribute` strategy is available for customers with simpler needs but should not
be the path of least resistance for a platform claiming to handle fintech,
healthcare, and iGaming domains.

**Container-per-customer isolation.**
Rejected. Container overhead eliminates the infrastructure cost advantage that
is a central Foundry product claim. PostgreSQL schema isolation provides sufficient
data separation. BEAM process isolation handles session separation. The combination
is appropriate for the target use case without the operational complexity and cost
of container orchestration per customer.

**`mix foundry.eject` task for no-lock-in guarantee.**
Rejected as unnecessary. Foundry is a tooling layer over a standard Elixir
application. The application has no runtime dependency on Foundry. There is nothing
to eject from — the customer already owns a standard Elixir app. Implementing an
eject task would create the false impression that the application is somehow
wrapped or owned by Foundry, which contradicts the structural reality.