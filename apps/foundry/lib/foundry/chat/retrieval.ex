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
        proposal_status: summarize_proposal(session_digest),
        scenario_coverage: summarize_scenarios(cached_context),
        retrieval_guidance:
          build_retrieval_guidance(
            project_root,
            modules,
            documents,
            module_contexts,
            document_contexts
          )
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

    Treat Project Status, System Architecture, and this Foundry Retrieval Summary
    as already-loaded global context. Reuse them before issuing shell discovery.
    Do not re-fetch `project_status` or `system_graph` in the same turn unless
    the injected context is stale, missing, or you need exact source evidence.
    The system map answers "which"; file or shell reads should answer "what"
    only when the retrieval summary is insufficient. When shell inspection is
    needed, batch related discovery and grouped file reads instead of inspecting
    one file at a time.

    ```json
    #{Jason.encode!(tool_results, pretty: true)}
    ```
    """
  end

  @spec create_proposal(String.t(), String.t(), map(), map(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def create_proposal(message, requester, tool_results, session_digest, project_root) do
    preview = proposal_preview(message, tool_results, project_root)

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

  @spec proposal_preview(String.t(), map(), String.t()) :: map()
  def proposal_preview(message, tool_results, project_root) do
    build_proposal_preview(message, tool_results, project_root)
  end

  @spec change_prompt(map()) :: String.t()
  def change_prompt(%{proposal: proposal, tool_results: tool_results}) do
    """
    ## Governed Change Run

    You are acting as a governed proposal author, not a file editor.
    Advance this change by following the three-part sequence below.
    Do not apply files directly. Produce a governed proposal response.

    ```json
    #{Jason.encode!(%{proposal: proposal, retrieval: tool_results}, pretty: true)}
    ```

    ### (a) Spec-kit requirements
    Cite every NodeEntry constraint relevant to this change: ADR references,
    compliance requirement IDs (INV-001..INV-018), runbook obligations, and
    @description field contracts on touched attributes. State any spec-kit artifact
    (ADR draft / runbook stub) that must be produced before code is written.

    ### (b) Igniter operation schema
    Emit the exact Igniter operation payload this proposal should execute, scoped to
    the modules identified in the retrieval results. Use the
    Foundry.Studio.ChatProposal operation format. Do not invent operations outside
    the schema.

    ### (c) Affected modules and test skeletons
    List every module that will be read, written, or deleted. For each written module,
    provide a minimal ExUnit test skeleton derived from the DSL declarations and ADR
    boundary conditions already loaded. Do not write implementation code.

    After completing (a), (b), and (c), state the proposal ID and whether auto-apply
    is permitted based on the change class in the proposal metadata above.
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

  defp summarize_scenarios(_cached_context) do
    report = Foundry.Context.ScenarioCache.get()

    if is_nil(report) do
      %{status: :unavailable}
    else
      warnings = report.warnings || []
      coverage = report.coverage || %{}
      uncovered = coverage_uncovered_node_ids(coverage)

      %{
        scenario_count: length(report.scenarios || []),
        warnings: Enum.take(warnings, 5),
        uncovered_node_count: length(uncovered),
        uncovered_nodes: Enum.take(uncovered, 10),
        failing_scenarios:
          report.scenarios
          |> List.wrap()
          |> Enum.filter(&(&1.trace_status == :failed))
          |> Enum.map(&%{id: &1.id, title: &1.title})
          |> Enum.take(10)
      }
    end
  end

  defp build_retrieval_guidance(
         project_root,
         modules,
         documents,
         module_contexts,
         document_contexts
       ) do
    module_files =
      module_contexts
      |> Enum.flat_map(fn module_context ->
        case module_source_path(module_context_module(module_context), project_root) do
          nil -> []
          path -> [Path.relative_to(path, project_root)]
        end
      end)
      |> Enum.uniq()

    document_paths =
      document_contexts
      |> Enum.map(& &1.path)
      |> Enum.uniq()

    file_hints = Enum.take(module_files ++ document_paths, 6)

    %{
      inferred_module_ids: modules,
      inferred_document_paths: Enum.map(documents, & &1.path),
      related_file_hints: file_hints,
      grouped_shell_plan: grouped_shell_plan(modules, file_hints)
    }
  end

  defp grouped_shell_plan([], []) do
    "Reuse the injected retrieval summary first. Do not shell-search for AGENTS.md, module names, or spec-kit paths — these are already in your system prompt. If source evidence is still required, run one grouped discovery command followed by one grouped read command."
  end

  defp grouped_shell_plan(modules, file_hints) do
    module_hint =
      modules
      |> Enum.map(&short_module_name/1)
      |> Enum.join(", ")

    file_hint =
      file_hints
      |> Enum.take(4)
      |> Enum.join(", ")

    [
      "Reuse the injected retrieval summary before any global refetch.",
      "Do not shell-search for AGENTS.md, module names, or spec-kit paths — these are already in your system prompt.",
      if(module_hint != "", do: "Start with grouped module discovery around #{module_hint}."),
      if(file_hint != "",
        do: "If exact source evidence is needed, inspect grouped files such as #{file_hint}."
      ),
      "Prefer one grouped discovery step and one grouped read step over one-file-at-a-time inspection."
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

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
      diff: build_unified_diff(files, message, tool_results),
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
        module = module_context_module(module_context)
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

  defp module_context_module(%{node: %{module: module}}) when is_binary(module), do: module
  defp module_context_module(%{id: id}) when is_binary(id), do: id
  defp module_context_module(_module_context), do: nil

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

    description =
      get_in(module_context, [:summary, :description]) ||
        "Refresh the module behavior and supporting copy."

    "Update #{module_name}: #{description}"
  end

  defp build_unified_diff([], message, tool_results), do: proposal_diff_placeholder(message, tool_results)

  defp build_unified_diff(files, _message, _tool_results) do
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
        "type" => "foundry.retrieval.summary",
        "phase" => "retrieval",
        "message" => "Prepared cached project status and system graph summary"
      }
    ]

    module_events =
      Enum.map(tool_results.module_contexts, fn module_context ->
        output =
          try do
            Jason.encode!(
              %{id: module_context.id, summary: module_context.summary, node: module_context.node},
              pretty: true
            )
          rescue
            _ -> inspect(module_context.summary, pretty: true)
          end

        %{
          "provider" => "foundry",
          "type" => "foundry.tool.module_context",
          "phase" => "retrieval",
          "tool" => "module_context",
          "path" => module_context.id,
          "message" => "Loaded module context for #{module_context.id}",
          "output" => output
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
          "message" => "Read spec-kit document #{document.path}",
          "output" => document.excerpt
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
      (tool_results[:module_contexts] || [])
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

  defp coverage_uncovered_node_ids(%{uncovered_node_ids: uncovered_node_ids})
       when is_list(uncovered_node_ids),
       do: uncovered_node_ids

  defp coverage_uncovered_node_ids(_coverage), do: []

  @doc """
  Builds business-fit signals for Phase A of the autoplan review pipeline (ADR-033).

  Returns a map with pattern match signals and spec-kit coverage indicators
  that `build_autoplan_review/3` uses to auto-resolve or surface Phase A questions.
  """
  @spec autoplan_context(String.t(), map()) :: map()
  def autoplan_context(project_root, retrieval) do
    nodes = retrieval[:project_status] || %{}
    module_contexts = retrieval[:module_contexts] || []
    documents = retrieval[:documents] || []

    pattern_match = find_pattern_match(module_contexts)
    spec_coverage = find_spec_coverage(documents, pattern_match)

    resources_touched =
      module_contexts
      |> Enum.map(& &1.id)
      |> Enum.filter(&resource_node?(project_root, &1))

    sensitive_resources =
      resources_touched
      |> Enum.filter(&sensitive_resource?(project_root, &1))

    migration_needed =
      case nodes do
        %{"pending_migrations" => migrations} when is_list(migrations) -> migrations != []
        _ -> false
      end

    %{
      pattern_match: pattern_match,
      spec_coverage: spec_coverage,
      resources_touched: resources_touched,
      sensitive_resources_touched: sensitive_resources,
      migration_needed: migration_needed,
      side_effect_count: estimate_side_effects(module_contexts),
      reactor_boundary_unclear: false,
      class_ambiguous: false
    }
  end

  defp find_pattern_match(module_contexts) do
    module_contexts
    |> Enum.find_value(fn ctx ->
      case ctx do
        %{node: %{pattern_examples: [ex | _]}} -> ex
        %{node: %{"pattern_examples" => [ex | _]}} -> ex
        _ -> nil
      end
    end)
  end

  defp find_spec_coverage(_documents, nil), do: false

  defp find_spec_coverage(documents, _pattern) do
    Enum.any?(documents, fn doc ->
      (doc[:type] || doc["type"]) in ["adr", "runbook"]
    end)
  end

  defp resource_node?(project_root, module_id) do
    case ProjectContext.build_one(project_root, module_id) do
      {:ok, node} -> Map.get(node, :kind) == "resource" or Map.get(node, "kind") == "resource"
      _ -> false
    end
  rescue
    _ -> false
  end

  defp sensitive_resource?(project_root, module_id) do
    case ProjectContext.build_one(project_root, module_id) do
      {:ok, node} -> Map.get(node, :sensitive) == true or Map.get(node, "sensitive") == true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp estimate_side_effects(module_contexts) do
    module_contexts
    |> Enum.flat_map(fn ctx ->
      node = ctx[:node] || ctx["node"] || %{}
      (node[:side_effects] || node["side_effects"] || [])
    end)
    |> length()
  end
end
