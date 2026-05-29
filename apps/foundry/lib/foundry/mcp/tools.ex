defmodule Foundry.MCP.Tools do
  @moduledoc """
  MCP tools for Foundry agents.

  These are simple function wrappers around Ash resources that return
  fully serialized JSON data suitable for MCP protocol responses.
  """

  require Ash.Query

  def project_status(args) do
    project_root = args["project_root"] || File.cwd!()

    case Foundry.Project.Status |> Ash.read!(domain: Foundry.Context, context: %{project_root: project_root}) do
      [record | _] -> {:ok, struct_to_map(record)}
      [] -> {:error, :not_found}
      error -> error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def module_context(args) do
    project_root = args["project_root"] || File.cwd!()
    module_id = args["module_id"]

    # Build filter manually
    query = Foundry.Project.Module
    filtered_query = if module_id, do: Ash.Query.filter(query, id: module_id), else: query

    case Ash.read!(filtered_query, domain: Foundry.Context, context: %{project_root: project_root}) do
      [record | _] -> {:ok, struct_to_map(record)}
      [] -> {:error, :not_found}
      error -> error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def system_graph(args) do
    project_root = args["project_root"] || File.cwd!()

    case Foundry.Project.Graph |> Ash.read!(domain: Foundry.Context, context: %{project_root: project_root}) do
      [record | _] -> {:ok, struct_to_map(record)}
      [] -> {:error, :not_found}
      error -> error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def run_lint(args) do
    project_root = args["project_root"] || File.cwd!()

    case Foundry.Lint.Run |> Ash.read!(domain: Foundry.Context, context: %{project_root: project_root}) do
      [record | _] -> {:ok, struct_to_map(record)}
      [] -> {:error, :not_found}
      error -> error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def read_doc(args) do
    project_root = args["project_root"] || File.cwd!()
    doc_id = args["id"]

    query = Foundry.SpecKit.Document
    filtered_query = if doc_id, do: Ash.Query.filter(query, id: doc_id), else: query

    case Ash.read!(filtered_query, domain: Foundry.Context, context: %{project_root: project_root}) do
      [record | _] -> {:ok, struct_to_map(record)}
      [] -> {:error, :not_found}
      error -> error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp struct_to_map(record) when is_struct(record) do
    record
    |> Map.from_struct()
    |> clean_metadata()
  end

  defp struct_to_map(other), do: other

  defp clean_metadata(map) do
    Map.drop(map, [
      :__meta__,
      :__metadata__,
      :__lateral_join_source__,
      :__order__,
      :aggregates,
      :calculations
    ])
  end
end
