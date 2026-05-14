defmodule FoundryWeb.GraphSemanticsTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../..", __DIR__)
  @semantics_path Path.join(@root, "apps/foundry_web/assets/js/graph/semantics.js")
  @normalizers_path Path.join(@root, "apps/foundry_web/assets/js/graph/normalizers.js")
  @fixture_path Path.join(@root, "apps/foundry_web/test/support/fixtures/igaming_context.json")

  test "legend semantics use boundary wording and keep adapter vocabulary centralized" do
    result =
      run_js("""
      const semantics = await importModule(#{js_string_literal(@semantics_path)})
      const legend = semantics.getBoundaryKindLegend()
      const nodes = semantics.getNodeKindLegend()

      printJson({
        section: semantics.LEGEND_SECTION_LABELS.boundaryKinds,
        boundary_labels: legend.map(item => item.label),
        adapter_label: nodes.find(item => item.type === 'adapter')?.label,
        blueprint_label: nodes.find(item => item.type === 'blueprint')?.label,
      })
      """)

    assert result["section"] == "Boundaries"
    assert "Domain group" in result["boundary_labels"]
    assert "Resource boundary" in result["boundary_labels"]
    assert result["adapter_label"] == "Adapter"
    assert result["blueprint_label"] == "Blueprint (legacy)"
    refute Enum.any?(result["boundary_labels"], &String.contains?(&1, "cluster"))
  end

  test "tooltip semantics use domain and agent step labels without leaking cluster" do
    result =
      run_js("""
      const semantics = await importModule(#{js_string_literal(@semantics_path)})

      printJson({
        domain_label: semantics.getTypeDisplayLabel({ id: 'domain:Finance', nodeKind: 'cluster', type: 'cluster' }),
        agent_label: semantics.getTypeDisplayLabel({ type: 'agent' }),
        adapter_label: semantics.getTypeDisplayLabel({ type: 'adapter' }),
      })
      """)

    assert result["domain_label"] == "domain"
    assert result["agent_label"] == "agent step"
    assert result["adapter_label"] == "adapter"
  end

  test "compliance helpers scope indicators to compliance-linked top-level nodes only" do
    result =
      run_js("""
      const semantics = await importModule(#{js_string_literal(@semantics_path)})

      const linkedGap = {
        nodeKind: 'entity',
        reqs: ['RG-1'],
        compliance_gap: true,
        cov: 34,
      }

      const plainNode = {
        nodeKind: 'entity',
        reqs: [],
        compliance_gap: false,
        cov: 100,
      }

      const childStep = {
        nodeKind: 'step',
        reqs: ['RG-1'],
        compliance_gap: true,
        cov: 100,
      }

      printJson({
        linked_gap_indicator: semantics.shouldShowComplianceGap(linkedGap),
        plain_node_indicator: semantics.shouldShowComplianceIndicator(plainNode),
        plain_node_coverage: semantics.shouldShowCoverageIndicator(plainNode),
        child_step_indicator: semantics.shouldShowComplianceIndicator(childStep),
        compliance_status: semantics.getComplianceStatus(['RG-1'], { e2e_tests: false }),
      })
      """)

    assert result["linked_gap_indicator"]
    refute result["plain_node_indicator"]
    assert result["plain_node_coverage"]
    refute result["child_step_indicator"]
    assert result["compliance_status"]["hasGap"]
    assert result["compliance_status"]["label"] == "coverage gap"
  end

  test "normalizer preserves explicit compliance flags and provider to adapter mapping" do
    result =
      run_js("""
      const fs = await import('node:fs/promises')
      const normalizers = await importBundledModule([
        #{js_string_literal(@semantics_path)},
        #{js_string_literal(@normalizers_path)},
      ])
      const fixture = JSON.parse(await fs.readFile(#{js_string_literal(@fixture_path)}, 'utf8'))
      const wallet = fixture.nodes.find(node => node.id === 'Finance.Wallet')
      const session = fixture.nodes.find(node => node.id === 'Gaming.GameSession')

      printJson({
        wallet: normalizers.normalizeNode(wallet),
        session: normalizers.normalizeNode(session),
        provider: normalizers.normalizeNode({
          id: 'Demo.ProviderAdapter',
          type: 'provider',
          domain: 'Demo',
          compliance: ['RG-1'],
          test_coverage: { e2e_tests: false },
        }),
      })
      """)

    assert result["wallet"]["has_compliance_links"]
    refute result["wallet"]["compliance_gap"]
    refute result["session"]["has_compliance_links"]
    refute result["session"]["compliance_gap"]
    assert result["provider"]["type"] == "adapter"
    assert result["provider"]["has_compliance_links"]
    assert result["provider"]["compliance_gap"]
  end

  defp run_js(source) do
    bootstrap = """
    import { readFile } from 'node:fs/promises'

    const importModule = async (path) => {
      const source = await readFile(path, 'utf8')
      return import(`data:text/javascript,${encodeURIComponent(source)}`)
    }

    const importBundledModule = async (paths) => {
      const parts = []

      for (const path of paths) {
        let source = await readFile(path, 'utf8')
        source = source.replace(/^import[\\s\\S]*?from\\s+['\"][^'\"]+['\"]\\s*;?\\n?/gm, '')
        parts.push(source)
      }

      return import(`data:text/javascript,${encodeURIComponent(parts.join('\\n\\n'))}`)
    }

    const printJson = (value) => {
      console.log(JSON.stringify(value))
    }
    """

    {output, 0} =
      System.cmd(
        "node",
        ["--input-type=module", "-e", bootstrap <> "\n" <> source],
        cd: @root
      )

    output
    |> String.trim()
    |> Jason.decode!()
  end

  defp js_string_literal(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> then(&"'#{&1}'")
  end
end
