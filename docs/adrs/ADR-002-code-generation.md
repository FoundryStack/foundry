# ADR-002: Code Generation — Igniter for All Code, No String Interpolation

**Status:** Accepted — amended 2026-04 (Ash.Resource.Igniter discovery API, pre-proposal checks)
**Date:** 2026-03
**Deciders:** Platform team

---

## Context

The copilot must generate and modify Elixir source code. There are three approaches:

1. **String interpolation**: build Elixir code as strings, write to disk
2. **Catalogue of pre-built operation modules**: every generation goes through a named Op.* module
3. **Pattern-driven raw Igniter**: agent reads an existing project example, then uses Igniter API directly

String interpolation is simpler to implement. It is wrong for this use case.
A pre-built catalogue requires maintaining 20+ modules that must track every Ash DSL version
change — and it encodes domain-specific assumptions (iGaming blueprints, money attributes)
at the platform level where they don't belong.

## Decision

**All code generation uses raw Igniter, guided by project examples and Foundry conventions.
String interpolation for Elixir source is forbidden. There is no pre-built operation catalogue.**

For every new construct, the agent:
1. Fetches the closest existing project example: `mix foundry.pattern.find <type> --domain <D>`
2. Reads Foundry conventions: `cat .foundry/usage_rules/foundry_conventions.md`
3. Reads exact DSL API if needed: `mix foundry.exdoc <Module>`
   *(In interactive sessions, `get_docs` via Tidewave MCP returns the same data
   without a subprocess, consulting the exact locked versions. `mix foundry.exdoc`
   is used on the proposal branch where Tidewave is not running.)*
4. Generates via raw Igniter API, copying the pattern and applying conventions

**Before generating**, the agent runs two structured pre-checks using Ash's Igniter API
(programmatic, inside the `Igniter.Mix.Task` callback — not shell commands):

```elixir
# 1. Discover: confirm which resources exist and their domains
{igniter, resource_modules} = Ash.Resource.Igniter.list_resources(igniter)
{igniter, domain_modules}   = Ash.Domain.Igniter.list_domains(igniter)

# 2. Duplicate check: verify the relationship/attribute does not already exist
{igniter, exists?} = Ash.Resource.Igniter.defines_relationship(igniter, TargetModule, :name)
# → if exists?, abort with "relationship :name already declared on TargetModule"
```

`Ash.Resource.Igniter.list_resources/1` and `Ash.Domain.Igniter.list_domains/1` are the
authoritative project discovery functions (confirmed in Ash changelog; recently optimized
for large codebases). They crawl the lib directory AST-level, find `use Ash.Resource` and
`use Ash.Domain` declarations, and return module lists without requiring compilation.
These replace the generic `Application.spec(:modules)` scan in `mix foundry.project.context`
for the discovery step. Note: `mix igniter.list_resources` does NOT exist as a standalone
mix task. The API is programmatic: `Ash.Resource.Igniter.list_resources(igniter)`.

For new files: `Igniter.create_new_file/3` or `Igniter.Project.Module.create_module/3`.
For modifying existing files: `Igniter.Project.Module.find_and_update_module/3` with `Sourceror.Zipper`.
For multi-file operations: composed Igniter pipelines, all writing to `foundry/prop_<id>` branch.

**Why examples beat a pre-built catalogue:** An example from the actual codebase encodes
every Foundry convention already — `@moduledoc`, domain wiring, telemetry prefix, test stub
co-location — at the exact current Ash version, without any maintenance overhead. One working
example is worth more than a catalogue module that may drift from the current DSL.

**Two named thin wrappers are retained** for cases where the logic is Foundry-specific
metadata with no Igniter equivalent:
- `Op.AddComplianceLink` — updates the compliance registry (not an AST change)
- `Op.AddAgentStep` (Phase 8) — governance scaffold with dual-proposal cascade

All other generation uses raw Igniter directly.

## Rationale

String-based generation has three failure modes that compound in regulated systems:

**Structural invalidity**: generated Elixir strings can be syntactically valid but semantically wrong (missing `do`/`end`, wrong module nesting, incorrect attribute types). The compiler catches this, but only after the file is written and reviewed, creating a confusing edit → reject → regenerate loop.

**Formatting instability**: string-generated code doesn't match the project's formatter configuration. This creates noisy diffs where formatting changes are mixed with actual logic changes, making review harder.

**Incremental unsafety**: when modifying an existing file, string interpolation can accidentally overwrite adjacent code. Igniter's zipper operations are scoped to specific AST nodes and cannot affect sibling nodes.

Igniter's AST manipulation is the published tool for exactly this use case. It handles formatting, idempotency (applying the same operation twice is safe), and provides dry-run output as a structured diff.

## Migration Generation

Scaffold operations that add or modify resources, attributes, or relationships must also
generate the corresponding `ash_postgres` migration. The mechanism:

```
Agent generates resource/attribute/relationship change:
  → git checkout -b foundry/prop_<id>
  → Igniter apply to branch              (code change only)
  → mix ash.codegen <auto_name>          (on branch — full project context present)
  → read generated migration file
  → git diff main..foundry/prop_<id>     (captures code diff + migration diff together)
  → both shown in review panel
  → git checkout main                    (working tree untouched)

On approval:
  → git merge --ff-only foundry/prop_<id>
  → mix ash.migrate
  → git branch -D foundry/prop_<id>
```

The branch contains the full project state, so `mix ash.codegen` runs correctly with
all dependencies and config. The migration is part of the branch diff and therefore
part of the stale detection mechanism (ADR-009): if `main` has diverged on affected
files since the branch was cut, the proposal is STALE.

For `:sensitive` resources: the migration is classified at the same level as the code change.
A migration touching a sensitive resource's table requires dual approval (ADR-005, INV-001).

## Policy Self-Audit Before UI Generation

Before generating any LiveView component or UI action, the agent checks policy
compatibility using compiled DSL runtime introspection:

```elixir
# Get the semantic truth about who can do what — not text search
authorizers = Ash.Resource.Info.authorizers(MyApp.Finance.Wallet)
policies    = Ash.Resource.Info.policies(MyApp.Finance.Wallet)
actions     = Ash.Resource.Info.actions(MyApp.Finance.Wallet)
```

This is the "self-audit" pattern: before generating an "Approve" button for a regular
user, the agent inspects the policy manifest to confirm the `:approve` action is
accessible to that actor. If it is not, the button is either omitted or rendered as
disabled with the correct role requirement shown.

This check is added to the pre-generation checklist in AGENTS.md:
`□ Policy compatibility verified for all generated UI actions (Ash.Resource.Info.policies/1)`

## Authentication Scaffold

There is no `Op.AddAuthenticationResource` wrapper — authentication scaffolding uses
`ash_authentication`'s own published Igniter generators directly, the same way
the agent uses any other raw Igniter call. The agent fetches the `ash_authentication`
usage rules (`cat .foundry/usage_rules/ash_authentication.md`) and the closest
existing auth resource pattern before generating. The copilot does not synthesise
authentication code from training memory.

## Foundry Conventions File

`.foundry/usage_rules/foundry_conventions.md` is the replacement for the catalogue.
It documents what every new construct must include:

- Every new module: `@moduledoc` with purpose, sensitivity classification, compliance links
- Every new attribute: `description:` field stating the invariant it protects
- Every new Reactor: idempotency declaration, `@runbook` link, telemetry prefix
- Every new sensitive resource: `use AshPaperTrail.Resource`, `use AshArchival.Resource`
- Every new Transfer: steps list with types, rules list, compliance links

The agent reads this file as part of `speckit.checklist` before generating any new
construct. It is committed to the project repository and versioned alongside the code.

## Consequences

- All generation uses raw Igniter — no catalogue module to maintain or version
- The agent's pattern lookup (`mix foundry.pattern.find`) is the primary quality mechanism:
  idiomatic output comes from copying working project code, not from pre-built templates
- Agents must never use `File.write!/2` or `EEx.eval_string/2` on Elixir source files
- All generation writes to a `foundry/prop_<id>` git branch; the working tree is never
  touched until the proposal is approved and merged
- The diff for review is `git diff main..foundry/prop_<id>` — code and migration together
- Migration diffs are always included in proposals that touch resource structure