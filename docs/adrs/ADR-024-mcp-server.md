# ADR-024: MCP Server Architecture — Foundry as Governed Tool Server

**Status:** Accepted
**Date:** 2026-04
**Deciders:** Platform team
**Extends:** ADR-001 (stack), ADR-010 (LLM context), ADR-013 (copilot behavior)

---

## Context

Foundry was originally specified as a copilot engine that calls an LLM (ADR-010: Claude
Sonnet via LangChain). The ecosystem has evolved: Claude Code, Cursor, Codex CLI, and
Zed AI are mature AI agents that developers use inside their editors. These agents already
have their own LLM connections, their own API keys, and their own reasoning capabilities.

The question is no longer "how does Foundry call Claude" but "how do external AI agents
call Foundry's governed operations?"

The answer inverts the architecture: Foundry IS the MCP server. External agents connect
to it.

---

## Decision

**Foundry exposes its governed operations as an MCP server endpoint via `AshAi.Mcp.Router`.
External AI agents (Claude Code, Cursor, Codex CLI, Zed AI, any MCP-compatible tool)
connect to this endpoint and call Foundry's governed tools. Foundry does not initiate
LLM calls to serve these agents — it executes governed Elixir operations in response to
MCP tool calls.**

This is the Tidewave model applied to governance: Tidewave exposes runtime intelligence
(docs, eval, SQL). Foundry exposes governance intelligence (context, proposals, lint,
approvals). Both are MCP servers. Neither makes LLM calls.

---

## MCP Tool Surface

All tools are declared in `Foundry.Context` domain using `ash_ai`'s `tools do ... end` DSL.
Each call is authorized via `Ash.can?/3` with the authenticated developer as actor.

```elixir
defmodule Foundry.Context do
  use Ash.Domain, extensions: [AshAi]

  tools do
    tool :get_project_status,  Foundry.Project.Status,    :read
    tool :get_module_context,  Foundry.Project.Module,    :context
    tool :get_graph,           Foundry.Project.Graph,     :read
    tool :run_bash,            Foundry.Copilot.Shell,     :execute
    tool :submit_proposal,     Foundry.Proposals.Proposal, :submit
    tool :get_proposal,        Foundry.Proposals.Proposal, :read
    tool :lint_check,          Foundry.Lint.Run,          :check
    tool :read_spec_kit_doc,   Foundry.SpecKit.Document,  :read
  end
end
```

### Tool Specifications

| Tool | Returns | Authorization |
|---|---|---|
| `get_project_status` | `mix foundry.project.status` JSON — lint, migrations, proposals, compliance gaps | Any authenticated developer |
| `get_module_context` | NodeEntry JSON for one module (`mix foundry.project.context <Module>`) | Any authenticated developer |
| `get_graph` | Full NodeEntry + EdgeEntry list for the project | Any authenticated developer |
| `run_bash` | Shell output; constrained to ADR-010 permitted command list | Any authenticated developer; blocked commands return `{:error, :command_not_permitted}` |
| `submit_proposal` | Proposal ID + diff; runs Igniter on `foundry/prop_<id>` branch | Blocked by `Ash.Policy.Authorizer` for `:sensitive` resource changes until dual approval |
| `get_proposal` | Proposal state, diff, and approval status by ID | Any authenticated developer |
| `lint_check` | `mix foundry.lint.all` structured violations | Any authenticated developer |
| `read_spec_kit_doc` | Full text of ADR / runbook / regulation file via `Foundry.FileSystem.read/2` | Any authenticated developer; INV-018 boundary enforced |

### Router Setup

```elixir
# In Foundry's Phoenix router (local and cloud mode)
scope "/foundry/mcp" do
  pipe_through :foundry_api_key_auth

  forward "/", AshAi.Mcp.Router,
    tools: [
      :get_project_status, :get_module_context, :get_graph,
      :run_bash, :submit_proposal, :get_proposal,
      :lint_check, :read_spec_kit_doc
    ],
    otp_app: :foundry_studio
end

pipeline :foundry_api_key_auth do
  plug AshAuthentication.Strategy.ApiKey.Plug,
    resource: Foundry.Accounts.Developer,
    required?: true
end
```

### MCP Resource Surface (read-only content for agents)

In addition to tools, Foundry exposes spec-kit documents as MCP resources:

```elixir
mcp_resources do
  mcp_resource :agents_md, "file://spec-kit/AGENTS.md",
    Foundry.SpecKit.Document, :read_agents_md do
    mime_type "text/markdown"
    description "Primary context document for all agents working on this project"
  end

  mcp_resource :adr_index, "file://spec-kit/adrs",
    Foundry.SpecKit.Document, :list_adrs do
    mime_type "application/json"
    description "Index of all Architecture Decision Records with tags and summaries"
  end
end
```

---

## Two MCP Surfaces — Non-Overlapping

Foundry scaffolds target projects with Tidewave (dev-only). This creates two MCP servers
in development mode that serve different audiences and purposes:

| Surface | Package | Audience | Purpose |
|---|---|---|---|
| `/tidewave/mcp` | `tidewave` (dev only) | External agents (Claude Code, Cursor) developing *on* the target platform | Runtime intelligence: `get_docs`, `get_ash_resources`, `project_eval`, `execute_sql_query`, `get_logs` |
| `/foundry/mcp` | `ash_ai` (AshAi.Mcp.Router) | External agents submitting *governed changes* to the target platform | Proposal submission, context graph, lint, spec-kit documents |

These are additive. A developer using Claude Code in their editor connects to both:
- Tidewave gives Claude Code runtime intelligence about the *current* codebase
- Foundry gives Claude Code governed tools to *change* the codebase with audit trail

Neither server makes LLM calls. Both expose data and operations for external agents to use.

---

## Optional Internal LLM (Foundry's own reasoning)

Foundry's server-side optional reasoning uses `ash_ai` prompt-backed actions:

```elixir
# In Foundry.Copilot (cloud mode / no external agent attached)
action :classify_intent, :atom do
  constraints one_of: [:question, :change, :speckit, :ambiguous]
  argument :message, :string, allow_nil?: false

  run prompt(
    fn _input, _context ->
      ReqLLM.model!("anthropic:claude-sonnet-4-6")
    end,
    tools: false
  )
end
```

This path is **opt-in** and **bypassed when an external agent is handling reasoning**.
In local mode with Claude Code attached: Foundry executes tool calls; Claude Code reasons.
In cloud mode without an agent attached: Foundry's own prompt actions handle reasoning.

The model is configured in `manifest.exs` via `copilot.model` — defaults to
`"anthropic:claude-sonnet-4-6"` but can be changed per project.

---

## Rationale

**Why the architectural inversion is correct:**

External agents (Claude Code, Cursor) have better reasoning, larger context windows, and
more up-to-date training than any model Foundry could embed. Foundry's value is not in
its reasoning — it is in its governed execution: Igniter running on isolated branches,
change classification, dual approval for sensitive resources, audit trail, compliance
linkage. These are operations, not reasoning.

Making Foundry an MCP server means any AI agent can benefit from Foundry's governance
layer. Making Foundry an LLM client means Foundry must maintain its own model selection,
prompt engineering, and retry logic — work that agents handle better.

**Why INV-001 is still enforced:**

MCP tool calls go through `Ash.can?/3`. The `submit_proposal` action checks the
proposal's target resources against `manifest.sensitive_resources`. If the change
touches a sensitive resource and dual approval has not been granted, `Ash.can?/3`
returns `{:error, :unauthorized}`. The external agent sees the error, surfaces it to
the developer, and the developer initiates the approval flow in Foundry Studio. The
governance model is enforced at the data layer, not by trusting agents to self-police.

---

## Consequences

- ADR-010's "LLM model selection" section is amended: the model string is used only
  for Foundry's optional internal reasoning, not for serving external agents.
- `mix foundry.spec_kit.init` scaffolds Tidewave into the target project's endpoint.
- A single `.foundry/mcp_config.json` is generated by `mix foundry.spec_kit.init`
  for Claude Code integration, pointing to `/foundry/mcp` and `/tidewave/mcp`.
- The "Activity Feed copilot" in ADR-008/ADR-013 is reframed: it is still the primary
  human-facing interface in Foundry Studio, but it is now one of many ways to interact
  with Foundry. External agents interact via MCP; humans interact via Activity Feed.
  Both paths go through the same governed proposal lifecycle.
- Foundry's `mix.exs` no longer needs LangChain. The dependency list is:
  `ash_ai`, `req_llm` (for optional internal calls), `ash_diagram`, `spark_meta`,
  `spark_lint`, plus the ADR-001 core stack.