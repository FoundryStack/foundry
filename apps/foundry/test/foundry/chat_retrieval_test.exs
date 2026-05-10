defmodule Foundry.ChatRetrievalTest do
  use ExUnit.Case, async: true

  alias Foundry.Chat.Retrieval
  alias Foundry.Context.ProjectContext

  @project_root Path.expand("../../../../reference_projects/igaming", __DIR__)

  test "proposal_preview builds preview files from real NodeEntry structs" do
    {:ok, project_context} = ProjectContext.build(@project_root)

    rule_node =
      Enum.find(project_context.nodes, fn node ->
        node.type == "rule" and String.contains?(node.module, "Promotions.Rules")
      end)

    assert rule_node

    tool_results = %{
      project_status: %{},
      system_graph: %{},
      documents: [],
      proposal_status: nil,
      module_contexts: [
        %{
          id: rule_node.id,
          summary: %{
            module: rule_node.module,
            description: rule_node.description
          },
          node: rule_node
        }
      ]
    }

    preview =
      Retrieval.proposal_preview(
        "Implement promotion rule safeguards",
        tool_results,
        @project_root
      )

    assert preview.summary =~ "Campaign"
    assert preview.files != []

    assert Enum.any?(preview.files, fn file ->
             is_binary(file.path) and String.contains?(file.summary, "CampaignNotExpired")
           end)
  end

  test "prepare emits retrieval summary events instead of fake global tool usage" do
    {:ok, retrieval} =
      Retrieval.prepare(
        @project_root,
        "Review bonuses. Do you see implementation and test gaps?",
        %{}
      )

    types = Enum.map(retrieval.trace_events, & &1["type"])
    tools = Enum.map(retrieval.trace_events, & &1["tool"])

    assert "foundry.retrieval.summary" in types
    refute "foundry.tool.project_status" in types
    refute "foundry.tool.system_graph" in types
    refute "project_status" in tools
    refute "system_graph" in tools
  end

  test "tool_prompt includes reuse and batching guidance" do
    prompt =
      Retrieval.tool_prompt(%{
        tool_results: %{
          project_status: %{project: "igaming"},
          system_graph: %{node_count: 1},
          module_contexts: [],
          documents: [],
          proposal_status: nil,
          retrieval_guidance: %{
            inferred_module_ids: ["IgamingRef.Promotions.BonusGrant"],
            inferred_document_paths: ["docs/runbooks/bonus_grant_transfer.md"],
            related_file_hints: ["lib/promotions/bonus_grant.ex"],
            grouped_shell_plan: "Prefer one grouped discovery step and one grouped read step."
          }
        }
      })

    assert prompt =~ "already-loaded global context"
    assert prompt =~ "Do not re-fetch `project_status` or `system_graph`"
    assert prompt =~ "batch related discovery and grouped file reads"
    assert prompt =~ "grouped_shell_plan"
  end
end
