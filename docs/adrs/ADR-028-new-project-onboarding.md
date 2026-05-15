# ADR-028: New Project Onboarding and Agent Skills Distribution

**Status:** Proposed  
**Date:** 2026-05-15  
**Deciders:** Platform team

---

## Context

A new user opening Foundry needs a clear path to their first working project. Current experience has friction:

1. **Environment uncertainty** — user may not have Elixir, Node.js, or Bun installed; no clear guidance
2. **Scaffolding fragmentation** — mix, npm, Phoenix setup scattered across manual steps
3. **Spec-kit mystery** — user doesn't know what `.specify`, `.agents/`, AGENTS.md are; no bootstrap guidance
4. **Skills distribution unclear** — if Foundry is a Burrito binary, how do agent skills reach the copilot?
5. **File editing burden** — current flow suggests manual AGENTS.md edits; user should never touch files directly

The onboarding must be:
- **Copilot-first** — user interacts with copilot, not command line
- **Self-service dependency install** — detect missing runtimes, offer one-click fixes via nvm/homebrew
- **Skills in the project** — sandboxed copilot session must access agent skills locally, not from binary internals
- **Auto-bootstrap** — folder open → detection → guided setup → immediate copilot engagement

## Decision

### 1. Folder-Open Onboarding

Foundry's "New Project" flow mirrors VSCode:

```
User opens Foundry UI
  ↓
"Open folder" (File → Open)
  ↓
Foundry detects: mix.exs present?  .foundry/ directory present?
  ├─ Yes to both    → load project normally
  ├─ No (empty)     → show onboarding flow
  └─ Partial        → ask user: initialize or cancel?
```

No "Create new project" dialog. Opening a folder is the primary gesture.

### 2. Dependency Detection and One-Click Install

Before scaffolding, the UI shows:

```
Required Dependencies:
  ✓ Erlang 27.0+    [Installed]
  ✗ Elixir 1.17+    [Install via Homebrew] [Install via asdf] [Skip]
  ✗ Node.js 20+     [Install via nvm] [Install via Homebrew] [Skip]
  ○ Bun 1.0+        [Install via npm] [Skip]
```

**One-click install strategy:**
- `Homebrew` → runs `brew install elixir` (user must have Homebrew; install prompts if missing)
- `nvm` → runs `nvm install 20 && nvm use 20` (nvm must exist; install link provided if not)
- `asdf` → runs `asdf install` (reads .tool-versions)
- `Skip` → proceed with warning ("project may not run without X")

**Blocking rule:** Cannot proceed to scaffolding without Elixir and (Node.js OR Bun). This is a hard gate because:
- `mix phx.new` requires Elixir
- Asset builds require a JavaScript runtime

### 3. Native Phoenix Scaffolding with Umbrella

Foundry does not reinvent Phoenix scaffolding. Instead:

```elixir
# User prompted for:
#   - Project name: "my_platform"
#   - Umbrella: yes/no

# Foundry runs:
mix phx.new my_platform --umbrella

# Umbrella structure created:
#   apps/my_platform/         (main Phoenix app)
#   apps/my_platform_web/     (LiveView + routes)
#   apps/my_platform_core/    (domain logic, optional)
```

Umbrella is the default because regulated platforms need separation of concerns:
- Core domain (Ash resources, Reactors, business rules)
- Web layer (Phoenix, LiveView, API routes)
- External integrations (optional separate app)

### 4. Spec-Kit Initialization and `.specify/` Directory Structure

After Phoenix scaffolds, Foundry runs `mix foundry.spec_kit.init`, which creates:

```
project/.agents/
  ├─ skills/
  │   ├─ speckit-specify.md          ← Foundry-provided templates
  │   ├─ speckit-plan.md
  │   ├─ speckit-clarify.md
  │   ├─ speckit-implement.md
  │   ├─ speckit-analyze.md
  │   ├─ foundry-context-gather.md
  │   ├─ foundry-spec-navigator.md
  │   ├─ foundry-plan-architect.md
  │   └─ custom/                    ← Project extends/customizes
  │
  └─ settings.json                 ← Claude Code config (hooked to copilot)

project/.specify/
  ├─ memory/                        ← Session state, findings (gitignored)
  ├─ scripts/                       ← Custom spec-kit automation
  ├─ templates/                     ← ADR, runbook, regulation stubs
  └─ foundry_extensions.exs         ← Custom Spark extensions for this project
```

**Why skills live in the project, not the Foundry binary:**
- Copilot runs sandboxed in the project root; cannot reliably access parent binary internals
- Each project can customize/extend skills without affecting Foundry distribution
- Projects are portable: move folder, Foundry still works (no binary path dependencies)
- Skills are versioned with the project via `.agents/skills/` committed to git

**Foundry's role:** On `spec_kit.init`, Foundry provides skill templates (Markdown stubs for each agent skill). Project gets local copies.

### 5. Copilot-First Onboarding Message

After scaffolding completes, Foundry:

```
1. Creates .foundry/manifest.exs          (project config)
2. Creates docs/adrs/, docs/runbooks/, docs/regulations/  (directories)
3. Creates template AGENTS.md with Foundry defaults
4. Auto-opens Copilot with seed message:

   "I've created a new Foundry project. 
    
    Help me define the domains and initial requirements:
    • What are the main business domains?
    • What's the first resource I'll build?
    • What compliance requirements apply?
    
    Use speckit.specify to gather requirements and I'll 
    draft your AGENTS.md, ADRs, and first resources."
```

Copilot then runs `speckit.specify` interview without waiting for user request.

### 6. No Manual File Editing

Users **never edit AGENTS.md, ADRs, or project structure manually.** All modifications go through copilot proposals:

```
User:        "Add a Withdrawal resource to Finance domain"
Copilot:     → runs speckit.plan, speckit.specify, etc.
             → generates AGENTS.md updates, migration, tests, code
             → shows review panel with proposals
User:        Approves
Copilot:     → applies changes
```

AGENTS.md is system-generated from user intent via copilot. Manual edits are discouraged (future: lint warning if AGENTS.md was edited outside copilot).

## Rationale

**Folder-open onboarding:**
- Users expect it (VSCode, Cursor, etc.); discoverable gesture
- Avoids "new project" ceremony and configuration dialogs
- Project detection is deterministic: check for mix.exs and .foundry/

**One-click dependency install:**
- Regulated domains have strict requirements: teams can't proceed without proper tooling
- Foundry is packaging Burrito binary for standalone use; help users complete their environment
- nvm/homebrew are platform-standard; failures are transparent and fixable
- Blocking on missing dependencies prevents silent failures during first build/compile

**Native Phoenix scaffolding:**
- `mix phx.new` is idiomatic, battle-tested, tracks Elixir evolution
- Foundry doesn't maintain a forked generator; delegation reduces maintenance
- Umbrella is standard for regulated platforms (separation of concerns, deployment flexibility)

**Skills in project, not binary:**
- Sandboxing: copilot's working directory is project root; file access is scoped
- Portability: binary path dependencies (e.g., `/usr/local/foundry/...`) break when moving projects or Foundry updates location
- Customization: project-specific skill extensions don't pollute Foundry distribution
- Version alignment: skills.md and project code co-evolve in git history

**Copilot-first seed message:**
- User sees copilot as the primary interface, not CLI commands
- Structured interview (speckit.specify) is less intimidating than blank AGENTS.md
- Copilot generates system artifacts → user reviews in one panel → reduces context switching

**No manual editing:**
- Source of truth is copilot decision history, not file timestamps
- Diffs are always reviewed proposals; no silent file changes
- Reduces user confusion ("did I change this or did the tool?")
- Future: lint can warn on out-of-band file edits

## Consequences

- Foundry requires Burrito packaging to provide a standalone binary with dependency install UX
- `.agents/skills/` is a committed directory in every project; skill updates require a proposal
- Projects cannot share skill customizations without a monorepo structure; worth addressing in future
- Copilot is the **only** way to modify platform definition (AGENTS.md, ADRs, spec-kit)
- Bootstrap projects start with a filled-in copilot session, not a blank editor

## Alternatives Considered

**Auto-install all dependencies without user prompts:**
- Rejected: too fragile (shell paths, version conflicts, permissions). Better to show options and let user choose.

**Keep agent skills in Foundry binary, make them accessible via MCP:**
- Rejected: MCP tools are for target platform integrations, not Foundry internals. Copilot needs local, fast access to skill definitions during iteration.

**Scaffold custom `.foundry/` directory instead of `.specify/`:**
- Rejected: `.specify/` separates spec-kit memory/scripts/templates (user-specific) from Foundry config (shared). Clear boundaries.

**Manual AGENTS.md editing with linting:**
- Rejected: preventive design is better than detective design. If the tool can prevent confusion, it should.

**Require `mix foundry.spec_kit.init` as separate command:**
- Rejected: User shouldn't know this exists. Part of the onboarding flow, transparent to them.

---

## Related ADRs

- **ADR-008** — Read-only system map, Activity Feed as change interface
- **ADR-013** — Copilot agent behavior, clarifying question UX, interview structure
- **ADR-015** — Storage model (git-backed, no Postgres dependency)
- **ADR-020** — Project context filesystem and umbrella support
- **ADR-024** — MCP server architecture (Foundry is the server; this ADR is about internal skills, not external integrations)
