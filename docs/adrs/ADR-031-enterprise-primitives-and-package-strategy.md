# ADR-028: Enterprise Primitives and Package Governance Strategy

## Status

Accepted

## Context

Foundry’s target users build platforms in regulated domains (fintech, iGaming, healthcare). These domains require complex, distributed, and compliance-heavy logic such as the 4-eyes principle (maker-checker), idempotency, bitemporal querying, dynamic PII redaction, and strict data retention limits.

Currently, if an AI agent is instructed to implement these features, it attempts to generate them from scratch using low-level Elixir, raw SQL, or complex custom state machines. This leads to:

1. High rates of hallucination and fragile code.
2. Silent compliance failures (e.g., race conditions in financial ledgers).
3. Massive, difficult-to-review diffs in the proposal queue.

We need to restrict the AI's vocabulary to a set of proven, declarative "Golden Standard" primitives. However, we must strictly adhere to the principle of not reinventing the wheel if a solution already exists in the Ash Framework or Erlang/Elixir ecosystems.

## Decision

We will adopt a **3-Tier Package Strategy** for enterprise features. The Foundry copilot will be trained to use these packages declaratively via the Spark DSL, rather than generating imperative logic.

### Tier 1: Curate (Mandate Existing Ash Extensions)

Where the Ash core team has already built a solution, Foundry will not build an alternative. Foundry will generate code that utilizes these packages by default:

- **`ash_oban`**: For all Transactional Outbox/Inbox patterns and guaranteed background jobs.
- **`ash_cloak`**: For PCI/HIPAA compliant at-rest data encryption (Secure Tokens).
- **`ash_double_entry` & `ash_money`**: For all financial ledgers and multi-currency transactions.
- **`ash_paper_trail` & `ash_archival`**: Mandatory for all `:sensitive` resources (enforced via INV-011 and INV-012).

### Tier 2: Bridge (Wrap Existing BEAM Ecosystem)

Where the Elixir/Erlang ecosystem has robust libraries but Ash lacks a native declarative extension, Foundry will build lightweight Spark DSL wrappers. This gives the AI a simple interface to complex BEAM tools:

- **`ash_idempotency`**: Wraps Ecto unique constraints or Redis locks to enforce INV-020 (Idempotency on external side-effects) declaratively via `idempotent true`.
- **`ash_velocity`**: Wraps Elixir's `hammer` library to provide sliding-window rate limits as native Ash Action validations.
- **`ash_circuit_breaker`**: Wraps Erlang's `:fuse` to protect `ash_oban` workers and `Reactor` external side-effects from cascading failures.
- **`foundry_governed_flags`**: Wraps `fun_with_flags`, integrating it with Foundry's compliance engine to enforce INV-013 (Compliance-gated feature flags must have ADR links).

### Tier 3: Innovate (Greenfield Enterprise Extensions)

Where neither Ash nor Elixir provides a generalized solution for a regulatory requirement, Foundry will build proprietary, open-source Spark extensions:

- **`ash_maker_checker`**: A 4-eyes principle engine that intercepts changes, routes them to an approval queue, and requires a second actor to authorize.
- **`ash_redact`**: A dynamic data-masking extension to redact PII based on actor context before data reaches the presentation layer.
- **`ash_data_portability`**: An automated graph-walker that traverses Ash relationships to generate GDPR Subject Access Request (SAR) exports.
- **`ash_retention`**: A declarative TTL engine that automatically enforces regulatory data pruning and cold-storage archiving.
- **`ash_jurisdiction`**: A multi-region policy router that dynamically scopes queries and policies based on user geography.

## Consequences

### Positive

- **Reduced Hallucination:** The AI agent transitions from "writing complex logic" to "configuring proven libraries," drastically reducing the surface area for bugs.
- **Guaranteed Compliance:** By using standard primitives, Foundry can mathematically guarantee that idempotency, PII redaction, and audit trails are implemented correctly.
- **Faster Review Cycles:** Human reviewers will see a 1-line DSL addition (e.g., `retention policy: :delete, after: "7y"`) instead of 300 lines of custom cron-job logic, making the review panel highly efficient.

### Negative

- **Maintenance Burden:** The Foundry core team must build and maintain the Tier 2 and Tier 3 extensions.
- **Dependency Bloat:** Target platforms will rely on a larger number of Hex packages, though this is mitigated by Foundry's strict dependency governance (ADR-004).

## Related Invariants

- **INV-011 / INV-012**: Sensitive resource audit & archival (Utilizes Tier 1).
- **INV-013**: Compliance-gated feature flags (Utilizes Tier 2).
- **INV-020**: Idempotency on external side effects (Utilizes Tier 2).
