defmodule FoundryWeb.McpToolDefinitions do
  @moduledoc """
  Defines MCP tools with complete metadata (name, description, parameter schemas).

  This ensures agents receive complete tool information and can reason about
  what tools do without having to speculatively read documentation.
  """

  def tools do
    [
      %{
        name: "project_status",
        description: "Get comprehensive status of the current Foundry project including domains, modules, lint errors, and stack versions",
        inputSchema: %{
          type: "object",
          properties: %{}
        }
      },
      %{
        name: "system_graph",
        description: "Retrieve the system architecture graph showing all modules, domains, pages, and their dependencies with visualization data",
        inputSchema: %{
          type: "object",
          properties: %{}
        }
      },
      %{
        name: "module_context",
        description: "Get detailed context for a specific module including its code, domain, type (controller/schema/service), and relationships",
        inputSchema: %{
          type: "object",
          properties: %{
            module_id: %{
              type: "string",
              description: "The module identifier (e.g., 'IgamingRef.Accounts.User'). If not provided, returns the first module."
            }
          }
        }
      },
      %{
        name: "run_lint",
        description: "Run Foundry linting to find architectural violations, unused code, and violations of project rules",
        inputSchema: %{
          type: "object",
          properties: %{}
        }
      },
      %{
        name: "read_doc",
        description: "Read a specification or architectural document from the project's .foundry/docs directory",
        inputSchema: %{
          type: "object",
          properties: %{
            id: %{
              type: "string",
              description: "The document identifier or path. If not provided, returns the first document."
            }
          }
        }
      },
      %{
        name: "submit_proposal",
        description: "Submit an architectural proposal (refactoring, new feature, or system change) for evaluation",
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description: "Title of the proposal"
            },
            description: %{
              type: "string",
              description: "Detailed description of the proposed change"
            },
            reasoning: %{
              type: "string",
              description: "Architectural reasoning for this proposal"
            }
          },
          required: ["title", "description", "reasoning"]
        }
      },
      %{
        name: "proposal_status",
        description: "Check the status of a previously submitted proposal",
        inputSchema: %{
          type: "object",
          properties: %{
            proposal_id: %{
              type: "string",
              description: "The unique proposal identifier"
            }
          }
        }
      },
      %{
        name: "edit_file",
        description: "Edit or create a source file with complete code replacement",
        inputSchema: %{
          type: "object",
          properties: %{
            path: %{
              type: "string",
              description: "File path relative to project root"
            },
            content: %{
              type: "string",
              description: "The complete file content"
            }
          },
          required: ["path", "content"]
        }
      }
    ]
  end

  def tool_by_name(name) do
    tools()
    |> Enum.find(&(&1.name == name))
  end
end
