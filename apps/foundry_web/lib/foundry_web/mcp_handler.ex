defmodule FoundryWeb.McpResourceHandler do
  @doc """
  Handle MCP resource requests by returning empty lists.

  Resources require Ash resource definitions with MCP metadata,
  which are pending modeling. For now, agents can access project
  data through the six available MCP tools instead:
  - project_status: get overall project info
  - module_context: read specific module implementation
  - system_graph: get architecture graph
  - run_lint: analyze code issues
  - read_doc: read spec-kit documentation
  """

  def handle_resources_list(_message, _opts) do
    %{"resources" => []}
  end

  def handle_resources_templates(_message, _opts) do
    %{
      "resourceTemplates" => [
        %{
          "name" => "project",
          "description" => "Project context via MCP tools",
          "mimeType" => "application/vnd.foundry.project",
          "uriTemplate" => "foundry://project/{id}"
        }
      ]
    }
  end

  def handle_resources_read(_message, _opts) do
    %{"error" => "resources/read not implemented"}
  end
end
