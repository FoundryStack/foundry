defmodule Foundry.SpecKit.Document do
  @moduledoc """
  Ash resource representing a spec-kit document (ADR, runbook, finding, regulation, or usage rule).

  Delegates to `Foundry.Context.SpecKitIndexBuilder.build/1` for enumeration
  and document metadata extraction.

  Each document has a path, title, type, summary, and extracted tags.
  """

  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Simple

  attributes do
    attribute :id, :string do
      description("Unique identifier derived from the document path.")
      primary_key?(true)
      allow_nil?(false)
    end

    attribute :path, :string do
      description(
        "Relative path from project root (e.g. 'docs/adrs/ADR-001-stack-selection.md')."
      )

      allow_nil?(false)
    end

    attribute :title, :string do
      description("Document title extracted from the filename or content.")
      allow_nil?(false)
    end

    attribute :type, :atom do
      description("Document type: :adr, :runbook, :finding, :regulation, :agents, :usage_rules.")
      allow_nil?(false)
    end

    attribute :summary, :string do
      description("First paragraph of the document, truncated to ~300 characters.")
      allow_nil?(true)
    end

    attribute :tags, {:array, :string} do
      description("Extracted keyword tags for search and filtering.")
      default([])
    end
  end

  actions do
    read :read do
      prepare fn query, _ ->
        project_root = query.context[:project_root] || File.cwd!()
        doc_filter = query.filter[Access.key(:id)]

        with {:ok, records} <- build_documents(project_root, doc_filter) do
          Ash.Query.load_data(query, records)
        else
          {:error, _} = error -> error
        end
      end
    end

    read :read_agents_md do
      description("Read the AGENTS.md spec-kit document.")

      prepare fn query, _ ->
        project_root = query.context[:project_root] || File.cwd!()

        with {:ok, content} <- Foundry.FileSystem.read(project_root, "AGENTS.md") do
          record = %{
            "id" => "agents",
            "path" => "AGENTS.md",
            "title" => "AGENTS.md",
            "type" => :agents,
            "summary" => String.slice(content, 0..300),
            "tags" => []
          }
          Ash.Query.load_data(query, [record])
        else
          _ -> Ash.Query.load_data(query, [])
        end
      end
    end

    read :read_adr_index do
      description("Read the ADR index JSON file.")

      prepare fn query, _ ->
        project_root = query.context[:project_root] || File.cwd!()

        with {:ok, index} <- Foundry.Context.SpecKitIndexBuilder.build(project_root)[:adrs] |> Jason.encode(),
             {:ok, _} <- Jason.decode(index) do
          record = %{
            "id" => "adr_index",
            "path" => "docs/adrs/index.json",
            "title" => "ADR Index",
            "type" => :adr,
            "summary" => "Architecture Decision Records index",
            "tags" => ["adr", "architecture", "decisions"]
          }
          Ash.Query.load_data(query, [record])
        else
          _ -> Ash.Query.load_data(query, [])
        end
      end
    end
  end

  defp build_documents(project_root, doc_filter) do
    spec_kit = Foundry.Context.SpecKitIndexBuilder.build(project_root) || %{}

    all_docs = []

    all_docs = all_docs ++ build_adr_docs(spec_kit)
    all_docs = all_docs ++ build_runbook_docs(spec_kit)
    all_docs = all_docs ++ build_regulation_docs(spec_kit)
    all_docs = all_docs ++ build_finding_docs(spec_kit)

    filtered = if doc_filter do
      Enum.filter(all_docs, &(&1["id"] == doc_filter))
    else
      all_docs
    end

    {:ok, filtered}
  catch
    _ -> {:error, :build_failed}
  end

  defp build_adr_docs(spec_kit) do
    (spec_kit["adrs"] || [])
    |> Enum.map(fn adr ->
      %{
        "id" => String.downcase(adr["id"] || ""),
        "path" => adr["path"] || "",
        "title" => adr["title"] || adr["id"] || "",
        "type" => :adr,
        "summary" => adr["summary"],
        "tags" => ["adr", "architecture"] ++ (adr["tags"] || [])
      }
    end)
  end

  defp build_runbook_docs(spec_kit) do
    (spec_kit["runbooks"] || [])
    |> Enum.map(fn runbook ->
      %{
        "id" => String.downcase(runbook["id"] || ""),
        "path" => runbook["path"] || "",
        "title" => runbook["title"] || runbook["id"] || "",
        "type" => :runbook,
        "summary" => runbook["summary"],
        "tags" => ["runbook"] ++ (runbook["tags"] || [])
      }
    end)
  end

  defp build_regulation_docs(spec_kit) do
    (spec_kit["regulations"] || [])
    |> Enum.map(fn reg ->
      %{
        "id" => String.downcase(reg["id"] || ""),
        "path" => reg["path"] || "",
        "title" => reg["title"] || reg["id"] || "",
        "type" => :regulation,
        "summary" => reg["summary"],
        "tags" => ["regulation", "compliance"] ++ (reg["tags"] || [])
      }
    end)
  end

  defp build_finding_docs(spec_kit) do
    (spec_kit["findings"] || [])
    |> Enum.map(fn finding ->
      %{
        "id" => String.downcase(finding["id"] || ""),
        "path" => finding["path"] || "",
        "title" => finding["title"] || finding["id"] || "",
        "type" => :finding,
        "summary" => finding["summary"],
        "tags" => ["finding"] ++ (finding["tags"] || [])
      }
    end)
  end
end
