defmodule Foundry.Context do
  @moduledoc """
  Ash domain exposing Foundry project context as MCP tools.

  This domain bridges the existing Mix tasks (`mix foundry.project.status`,
  `mix foundry.context`, `mix foundry.project.context`, `mix foundry.lint.all`,
  and spec-kit document reads) through Ash resources so they can be exposed as
  MCP tools via `AshAi.Mcp.Router`.

  ## Tools

  The `tools` block declares which resource actions are callable by AI agents
  through the MCP interface. Each tool maps to an Ash action on a resource
  using `Ash.DataLayer.Simple` — no database is involved.

  ## MCP Resources

  Static spec-kit documents (AGENTS.md, ADR index) are exposed as MCP resources
  so agents can read them directly without going through tool calls.

  ## ADR

  ADR-024 — MCP Server Architecture.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource Foundry.Project.Status
    resource Foundry.Project.Module
    resource Foundry.Project.Graph
    resource Foundry.Lint.Run
    resource Foundry.SpecKit.Document
    resource Foundry.Proposals.Proposal
    resource Foundry.FileOperations.Edit
    resource Foundry.MCP.DocReader
  end

  # MCP tools — each wraps an Ash action on a Simple data layer resource.
  # The tool names are the ergonomic names exposed to agents via MCP.
  tools do
    tool :project_status, Foundry.Project.Status, :read,
      description: "Get full project status: domains, lint counts, stack versions, compliance coverage, pending migrations, and recent activity."

    tool :module_context, Foundry.Project.Module, :read,
      description: "Get detailed context for modules in the project: type, domain, rules, compliance links, test coverage, state machine, agent steps. Returns all modules when no filter is given."

    tool :system_graph, Foundry.Project.Graph, :read,
      description: "Get the system architecture graph: all nodes (modules, domains, pages) and edges (relationships, rules, data flow) as a structured JSON graph."

    tool :run_lint, Foundry.Lint.Run, :read,
      description: "Run the Foundry lint rules against the project and return violations, warnings, and a pass/fail summary."

    tool :read_doc, Foundry.SpecKit.Document, :read,
      description: "Read spec-kit documents: ADRs, runbooks, regulations, and findings. Returns all documents when no filter is given; filter by id to read a specific document."

    tool :submit_proposal, Foundry.Proposals.Proposal, :create_draft,
      description: "Submit a change proposal (code edit, architecture decision, config change) for review. Returns a proposal ID to track status."

    tool :proposal_status, Foundry.Proposals.Proposal, :read,
      description: "Get the status of a submitted change proposal: draft, pending review, approved, or rejected."

    tool :edit_file, Foundry.FileOperations.Edit, :write,
      description: "Edit a file in the project. Supports raw content writes and Spark DSL-aware edits for Elixir modules."
  end

  # MCP resources — static documentation and reference data for agent context grounding.
  # Agents can read these directly via MCP resources/read without making tool calls.
  mcp_resources do
    mcp_resource :agents_guide, "foundry://docs/agents.md", Foundry.MCP.DocReader, :agents_guide,
      title: "Agents Guide",
      description: "Agent specifications, capabilities, and integration patterns",
      mime_type: "text/markdown"

    mcp_resource :adr_index, "foundry://docs/adrs/index.json", Foundry.MCP.DocReader, :adr_index_json,
      title: "Architecture Decision Records",
      description: "Architecture Decision Records index with links to all ADRs",
      mime_type: "application/json"

    mcp_resource :runbooks, "foundry://docs/runbooks/index.json", Foundry.MCP.DocReader, :runbooks_index_json,
      title: "Runbooks",
      description: "Operational runbooks for troubleshooting and incident response",
      mime_type: "application/json"

    mcp_resource :build_sequence, "foundry://docs/build-sequence.md", Foundry.MCP.DocReader, :build_sequence,
      title: "Build Sequence",
      description: "Foundry's build process, phases, and build system architecture",
      mime_type: "text/markdown"

    mcp_resource :implementation_summary, "foundry://docs/implementation.md", Foundry.MCP.DocReader, :implementation_summary,
      title: "Implementation Summary",
      description: "Current system implementation: components, flow diagrams, architecture",
      mime_type: "text/markdown"

    mcp_resource :lint_catalogue, "foundry://docs/lint-rules.md", Foundry.MCP.DocReader, :lint_catalogue,
      title: "Lint Catalogue",
      description: "Complete catalog of lint rules, checks, and code analysis capabilities",
      mime_type: "text/markdown"
  end
end
