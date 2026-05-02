defmodule Foundry.Chat.Retrieval do
  @moduledoc """
  Foundry-native retrieval and proposal orchestration for the Studio copilot.

  This keeps discovery inside Foundry first, and only sends compact, relevant
  context down to the provider.
  """

  alias Foundry.Chat.ContextCache
  alias Foundry.Context.ProjectContext

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

  @spec create_proposal(String.t(), String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def create_proposal(message, requester, tool_results, session_digest) do
    attrs = %{
      change_class: classify_change(message, tool_results),
      operation: "Foundry.Studio.ChatProposal",
      operation_params: %{
        "message" => message,
        "session_digest" =>
          Map.take(session_digest || %{}, ["last_proposal_id", "selected_nodes"])
      },
      diff: proposal_diff_placeholder(message, tool_results),
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
           operation: proposal.operation
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
      Enum.flat_map(["adrs", "runbooks", "regulations", "usage_rules"], fn key ->
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
