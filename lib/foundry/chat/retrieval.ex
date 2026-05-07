defmodule Foundry.Chat.Retrieval do
  @moduledoc """
  Foundry-native retrieval and proposal orchestration for the Studio copilot.

  This keeps discovery inside Foundry first, and only sends compact, relevant
  context down to the provider.
  """

  alias Foundry.Chat.ContextCache
  alias Foundry.Context.ProjectContext
  alias Foundry.SparkMeta.Helpers, as: SparkMetaHelpers

  @max_modules 3
  @max_documents 3

  @spec prepare(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def prepare(project_root, message, session_digest) do
    with {:ok, cached_context} <- ContextCache.get_or_build(project_root) do
      modules =
        infer_modules(cached_context.project_context[:nodes] || [], message, session_digest)

      documents = infer_documents(cached_context.project_context[:spec_kit] || %{}, message)

      module_contexts =
        Enum.flat_map(modules, fn module_id ->
          case ProjectContext.build_one(project_root, module_id) do
            {:ok, node} -> [%{id: module_id, summary: summarize_node(node), node: node}]
            {:error, _reason} -> []
          end
        end)

      document_contexts =
        Enum.flat_map(documents, fn doc ->
          case Foundry.FileSystem.read(project_root, doc.path) do
            {:ok, content} ->
              [%{path: doc.path, title: doc.title, type: doc.type, excerpt: excerpt(content)}]

            {:error, _reason} ->
              [%{path: doc.path, title: doc.title, type: doc.type, excerpt: doc.summary}]
          end
        end)

      tool_results = %{
        project_status: summarize_status(cached_context.status),
        system_graph: summarize_graph(cached_context.project_context),
        module_contexts: module_contexts,
        documents: document_contexts,
        proposal_status: summarize_proposal(session_digest)
      }

      {:ok,
       %{
         cached_context: cached_context,
         tool_results: tool_results,
         trace_events:
           build_tool_trace_events(cached_context, tool_results, message, session_digest)
       }}
    end
  end

  @spec tool_prompt(map()) :: String.t()
  def tool_prompt(%{tool_results: tool_results}) do
    """
    ## Foundry Retrieval Summary

    Use this Foundry-side retrieval before issuing any shell discovery. The
    system map answers "which"; file or shell reads should answer "what" only
    when the retrieval summary is insufficient.

    ```json
    #{Jason.encode!(tool_results, pretty: true)}
    ```
    """
  end

  @spec create_proposal(String.t(), String.t(), map(), map(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def create_proposal(message, requester, tool_results, session_digest, project_root) do
    preview = build_proposal_preview(message, tool_results, project_root)

    attrs = %{
      change_class: classify_change(message, tool_results),
      operation: "Foundry.Studio.ChatProposal",
      operation_params: %{
        "message" => message,
        "session_digest" =>
          Map.take(session_digest || %{}, ["last_proposal_id", "selected_nodes"])
      },
      diff: preview.diff,
      requester: requester,
      adr_link: infer_adr_link(tool_results)
    }

    case Foundry.Proposals.Proposal
         |> Ash.Changeset.for_create(:create_draft, attrs, domain: Foundry.Proposals)
         |> Ash.create() do
      {:ok, proposal} ->
        {:ok,
         %{
           id: proposal.id,
           state: proposal.state,
           change_class: proposal.change_class,
           requester: proposal.requester,
           adr_link: proposal.adr_link,
           operation: proposal.operation,
           preview: preview
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec change_prompt(map()) :: String.t()
  def change_prompt(%{proposal: proposal, tool_results: tool_results}) do
    """
    ## Governed Change Run

    This request is in `change` mode. Do not behave like a direct file editor.
    Work from the proposal metadata and Foundry retrieval results below:

    ```json
    #{Jason.encode!(%{proposal: proposal, retrieval: tool_results}, pretty: true)}
    ```

    Provide:
    1. the governed interpretation of the requested change,
    2. the expected spec-kit requirements,
    3. the likely affected modules and tests,
    4. next approval/apply expectations for this proposal.
    """
  end

  defp summarize_status(status) do
    %{
      project: status["project"],
      domains: status["domains"],
      lint: status["lint"],
      migrations: status["migrations"],
      proposals: status["proposals"],
      compliance: Map.take(status["compliance"] || %{}, ["total_requirements", "covered_count"]),
      ci: status["ci"]
    }
  end

  defp summarize_graph(project_context) do
    nodes = project_context[:nodes] || []
    edges = project_context[:edges] || []

    %{
      project: project_context[:project],
      node_count: length(nodes),
      edge_count: length(edges),
      domains:
        nodes
        |> Enum.map(& &1.domain)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.take(8)
    }
  end

  defp summarize_node(node) do
    %{
      module: node.module,
      type: node.type,
      domain: node.domain,
      description: node.description,
      sensitive: node.sensitive,
      compliance: node.compliance,
      adrs: node.adrs,
      runbook: node.runbook,
      pending_migrations: node.pending_migrations
    }
  end

  defp summarize_proposal(%{"last_proposal_id" => nil}), do: nil
  defp summarize_proposal(%{"last_proposal_id" => id}) when is_binary(id), do: %{id: id}
  defp summarize_proposal(_digest), do: nil

  defp build_proposal_preview(message, tool_results, project_root) do
    files =
      tool_results
      |> proposal_preview_files(message, project_root)
      |> Enum.take(4)

    graph_overlay = proposal_graph_overlay(tool_results)
    change_summary = Enum.map(files, &Map.fetch!(&1, :summary))

    %{
      summary: proposal_summary(message, tool_results, files),
      change_summary: change_summary,
      diff: build_unified_diff(files, message),
      files: files,
      graph_overlay: graph_overlay,
      actions: %{
        apply: true,
        revise: true,
        cancel: true
      }
    }
  end

  defp proposal_preview_files(tool_results, message, project_root) do
    module_files =
      Enum.flat_map(tool_results.module_contexts || [], fn module_context ->
        module = get_in(module_context, [:node, :module]) || module_context.id
        path = module_source_path(module, project_root)
        summary = module_preview_summary(module_context)

        case file_preview_entry(path, :modified, summary, project_root) do
          nil -> []
          file -> [file]
        end
      end)

    document_files =
      Enum.flat_map(tool_results.documents || [], fn document ->
        case file_preview_entry(
               Path.join(project_root, document.path),
               :modified,
               "Refresh #{document.title || document.path} guidance to match this proposal.",
               project_root
             ) do
          nil -> []
          file -> [file]
        end
      end)

    inferred_file =
      inferred_new_file(message, project_root)

    (module_files ++ document_files ++ List.wrap(inferred_file))
    |> Enum.uniq_by(& &1.path)
  end

  defp file_preview_entry(nil, _status, _summary, _project_root), do: nil

  defp file_preview_entry(path, status, summary, project_root) do
    with true <- is_binary(path),
         true <- File.exists?(path),
         {:ok, content} <- File.read(path),
         relative_path <- Path.relative_to(path, project_root) do
      diff = build_file_diff(relative_path, content, status)
      {added_lines, removed_lines} = diff_line_counts(diff)

      %{
        path: relative_path,
        status: status,
        summary: summary,
        diff: diff,
        full_content: content,
        added_lines: added_lines,
        removed_lines: removed_lines
      }
    else
      _ -> nil
    end
  end

  defp inferred_new_file(message, _project_root) do
    lowered = String.downcase(message)

    cond do
      String.contains?(lowered, "test") ->
        %{
          path: "test/foundry_web/live/copilot_proposal_preview_test.exs",
          status: :added,
          summary: "Add a focused LiveView test for proposal preview actions and rendering.",
          diff: build_new_file_diff("test/foundry_web/live/copilot_proposal_preview_test.exs"),
          full_content: """
          defmodule FoundryWeb.CopilotProposalPreviewTest do
            use FoundryWeb.ConnCase
          end
          """,
          added_lines: 3,
          removed_lines: 0
        }

      String.contains?(lowered, "copilot") or String.contains?(lowered, "chat") ->
        %{
          path: "apps/foundry_web/lib/foundry_web/live/copilot_proposal_preview.ex",
          status: :added,
          summary: "Add a preview helper module to shape proposal cards for Studio chat.",
          diff:
            build_new_file_diff(
              "apps/foundry_web/lib/foundry_web/live/copilot_proposal_preview.ex"
            ),
          full_content: """
          defmodule FoundryWeb.CopilotProposalPreview do
            @moduledoc false
          end
          """,
          added_lines: 3,
          removed_lines: 0
        }

      true ->
        nil
    end
  end

  defp proposal_summary(_message, tool_results, files) do
    module_names =
      tool_results.module_contexts
      |> Enum.map(&short_module_name(&1.id))
      |> Enum.take(3)

    case {module_names, files} do
      {[], []} ->
        "This proposal captures the requested change and prepares a reviewable diff before any apply step."

      {modules, _} when modules != [] ->
        "This proposal updates #{Enum.join(modules, ", ")} and packages the affected files as a reviewable draft before apply."

      {_, file_entries} ->
        paths = file_entries |> Enum.map(& &1.path) |> Enum.take(3)

        "This proposal stages changes across #{Enum.join(paths, ", ")} and keeps them reviewable before apply."
    end
  end

  defp proposal_graph_overlay(tool_results) do
    modified_nodes =
      Enum.map(tool_results.module_contexts || [], fn module_context ->
        %{
          id: module_context.id,
          label: short_module_name(module_context.id),
          tone: "warning"
        }
      end)

    %{
      nodes_added: [],
      nodes_modified: modified_nodes,
      edges_added: [],
      edges_removed: []
    }
  end

  defp module_preview_summary(module_context) do
    module_name = short_module_name(module_context.id)
    description = get_in(module_context, [:summary, :description]) || "Refresh the module behavior and supporting copy."
    "Update #{module_name}: #{description}"
  end

  defp build_unified_diff([], message), do: proposal_diff_placeholder(message, %{})

  defp build_unified_diff(files, _message) do
    files
    |> Enum.map(& &1.diff)
    |> Enum.join("\n")
  end

  defp build_file_diff(path, content, :modified) do
    preview_lines =
      content
      |> String.split("\n")
      |> Enum.take(8)

    """
    diff --git a/#{path} b/#{path}
    --- a/#{path}
    +++ b/#{path}
    @@
    -#{Enum.at(preview_lines, 0, "")}
    +#{Enum.at(preview_lines, 0, "")}  # proposed change
     #{Enum.at(preview_lines, 1, "")}
     #{Enum.at(preview_lines, 2, "")}
     #{Enum.at(preview_lines, 3, "")}
    """
    |> String.trim_trailing()
  end

  defp build_new_file_diff(path) do
    """
    diff --git a/#{path} b/#{path}
    new file mode 100644
    --- /dev/null
    +++ b/#{path}
    @@
    +# new proposal artifact
    """
    |> String.trim_trailing()
  end

  defp diff_line_counts(diff) do
    lines = String.split(diff || "", "\n")

    {
      Enum.count(lines, &(String.starts_with?(&1, "+") and not String.starts_with?(&1, "+++"))),
      Enum.count(lines, &(String.starts_with?(&1, "-") and not String.starts_with?(&1, "---")))
    }
  end

  defp module_source_path(module, project_root) do
    module
    |> to_module_atom()
    |> case do
      nil -> nil
      atom -> SparkMetaHelpers.module_source_path(atom)
    end
    |> case do
      nil ->
        nil

      path ->
        if is_binary(path) and Path.type(path) == :relative do
          Path.expand(path, project_root)
        else
          path
        end
    end
  end

  defp to_module_atom(module) when is_atom(module), do: module

  defp to_module_atom("Elixir." <> _ = module) do
    try do
      String.to_existing_atom(module)
    rescue
      _ -> nil
    end
  end

  defp to_module_atom(module) when is_binary(module) do
    try do
      String.to_existing_atom("Elixir." <> module)
    rescue
      _ -> nil
    end
  end

  defp to_module_atom(_), do: nil

  defp short_module_name(module_id) when is_binary(module_id) do
    module_id
    |> String.split(".")
    |> List.last()
  end

  defp build_tool_trace_events(cached_context, tool_results, message, session_digest) do
    base = [
      %{
        "provider" => "foundry",
        "type" => "foundry.context",
        "phase" => "context",
        "cache" => Atom.to_string(cached_context.cache),
        "fingerprint" => cached_context.fingerprint,
        "built_at" => cached_context.built_at,
        "message" => "Loaded cached Foundry context"
      },
      %{
        "provider" => "foundry",
        "type" => "foundry.tool.project_status",
        "phase" => "retrieval",
        "tool" => "project_status",
        "message" => "Loaded project status for the current workspace"
      },
      %{
        "provider" => "foundry",
        "type" => "foundry.tool.system_graph",
        "phase" => "retrieval",
        "tool" => "system_graph",
        "message" => "Loaded compact system graph context"
      }
    ]

    module_events =
      Enum.map(tool_results.module_contexts, fn module_context ->
        %{
          "provider" => "foundry",
          "type" => "foundry.tool.module_context",
          "phase" => "retrieval",
          "tool" => "module_context",
          "path" => module_context.id,
          "message" => "Loaded module context for #{module_context.id}"
        }
      end)

    document_events =
      Enum.map(tool_results.documents, fn document ->
        %{
          "provider" => "foundry",
          "type" => "foundry.tool.read_doc",
          "phase" => "retrieval",
          "tool" => "read_doc",
          "path" => document.path,
          "message" => "Read spec-kit document #{document.path}"
        }
      end)

    session_event = %{
      "provider" => "foundry",
      "type" => "foundry.session.digest",
      "phase" => "session",
      "message" => "Prepared session digest for this turn",
      "summary" => %{
        "recent_files" => Map.get(session_digest || %{}, "recent_files", []),
        "selected_nodes" => Map.get(session_digest || %{}, "selected_nodes", []),
        "recent_conclusions" => Map.get(session_digest || %{}, "recent_conclusions", []),
        "recent_findings" => Map.get(session_digest || %{}, "recent_findings", []),
        "message_preview" => String.slice(message, 0, 120)
      }
    }

    base ++ module_events ++ document_events ++ [session_event]
  end

  defp infer_modules(nodes, message, session_digest) do
    selected_nodes =
      session_digest
      |> Map.get("selected_nodes", [])
      |> Enum.filter(&is_binary/1)

    selected_matches =
      Enum.filter(nodes, fn node ->
        node.module in selected_nodes or Path.basename(node.module) in selected_nodes
      end)

    token_matches =
      nodes
      |> Enum.map(fn node -> {module_match_score(node, message), node} end)
      |> Enum.filter(fn {score, _node} -> score > 0 end)
      |> Enum.sort_by(fn {score, node} -> {-score, node.module} end)
      |> Enum.map(&elem(&1, 1))

    (selected_matches ++ token_matches)
    |> Enum.uniq_by(& &1.module)
    |> Enum.take(@max_modules)
    |> Enum.map(&trim_elixir_prefix(&1.module))
  end

  defp infer_documents(spec_kit, message) do
    docs =
      Enum.flat_map(["adrs", "runbooks", "findings", "regulations", "usage_rules"], fn key ->
        Map.get(spec_kit, key, [])
      end)

    docs
    |> Enum.map(fn doc -> {document_match_score(doc, message), doc} end)
    |> Enum.filter(fn {score, _doc} -> score > 0 end)
    |> Enum.sort_by(fn {score, doc} -> {-score, doc.path} end)
    |> Enum.take(@max_documents)
    |> Enum.map(&elem(&1, 1))
  end

  defp module_match_score(node, message) do
    haystack =
      [node.module, node.domain, node.description]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    message
    |> tokenize()
    |> Enum.count(&String.contains?(haystack, &1))
  end

  defp document_match_score(doc, message) do
    haystack =
      [doc.title, doc.summary, Enum.join(doc.tags || [], " ")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    message
    |> tokenize()
    |> Enum.count(&String.contains?(haystack, &1))
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9_]+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
  end

  defp excerpt(content) when is_binary(content) do
    content
    |> String.trim()
    |> String.slice(0, 1000)
  end

  defp classify_change(message, tool_results) do
    text = String.downcase(message)
    modules = tool_results.module_contexts || []

    cond do
      String.contains?(text, ["compliance", "regulation", "adr", "policy"]) ->
        :compliance

      Enum.any?(modules, fn module_context ->
        case module_context do
          %{node: %{sensitive: sensitive}} -> sensitive
          %{node: node} when is_struct(node) -> Map.get(node, :sensitive, false)
          _ -> false
        end
      end) ->
        :sensitive

      String.contains?(text, ["reactor", "rule", "transfer", "job", "workflow", "behavior"]) ->
        :behavioral

      true ->
        :structural
    end
  end

  defp proposal_diff_placeholder(message, tool_results) do
    affected_modules =
      tool_results.module_contexts
      |> Enum.map(& &1.id)
      |> Enum.join(", ")

    """
    Proposal requested from Studio chat.
    Message: #{message}
    Affected modules: #{affected_modules}
    """
  end

  defp infer_adr_link(tool_results) do
    tool_results.documents
    |> Enum.find_value(fn document ->
      if document.type == "adr", do: document.title
    end)
  end

  defp trim_elixir_prefix("Elixir." <> rest), do: rest
  defp trim_elixir_prefix(value), do: value
end
