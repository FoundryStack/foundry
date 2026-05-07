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
  end

  # MCP tools — each wraps an Ash action on a Simple data layer resource.
  # The tool names are the ergonomic names exposed to agents via MCP.
  tools do
    # Project health summary (lint, migrations, proposals, compliance gaps)
    tool :project_status, Foundry.Project.Status, :read

    # Single module context (equivalent to `mix foundry.context <Module>`)
    tool :module_context, Foundry.Project.Module, :read

    # Full system graph (equivalent to `mix foundry.project.context`)
    tool :system_graph, Foundry.Project.Graph, :read

    # Run lint and return results
    tool :run_lint, Foundry.Lint.Run, :read

    # Read a spec-kit document by path
    tool :read_doc, Foundry.SpecKit.Document, :read

    # Submit a new proposal (create action on Proposal resource)
    tool :submit_proposal, Foundry.Proposals.Proposal, :create_draft

    # Read a proposal by ID
    tool :proposal_status, Foundry.Proposals.Proposal, :read
  end

  # MCP resources intentionally disabled until the backing Ash actions are modeled
  # with return metadata compatible with the AshAi mcp_resource verifier.
end
