import { CytoscapeGraph } from './cytoscape_graph'
import { extractColors, getDomainColor, covColor, domainCoverage } from './graph/colors'
import { buildFoundryStyles, FOUNDRY_LAYOUT_OPTIONS, FOUNDRY_COMPOUND_COMPACTION } from './graph/styles'
import { normalizeNode } from './graph/normalizers'
import { buildCytoscapeElements } from './graph/elements'
import { entityTpl, domainClusterTpl, clusterTpl, stepTpl, actionTpl } from './graph/templates'
import { buildCanvasOverlays, searchMatch } from './graph/utils'
import { HTML_LABEL_CONFIG } from './graph/config'

export {
  covColor,
  domainCoverage,
  getDomainColor,
  normalizeNode,
  buildCytoscapeElements,
  entityTpl,
  domainClusterTpl,
  clusterTpl,
  stepTpl,
  actionTpl,
  searchMatch,
}

export function mountFoundryGraph(container, contextJson) {
  const colors = extractColors()

  const graph = new CytoscapeGraph(container, {
    style: buildFoundryStyles(colors),
    layoutOptions: FOUNDRY_LAYOUT_OPTIONS,
    compoundCompaction: FOUNDRY_COMPOUND_COMPACTION,
  })

  // Rebuild color-dependent stylesheet when theme changes
  new MutationObserver(() => {
    graph.cy.style(buildFoundryStyles(extractColors())).update()
  }).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['data-theme'],
  })

  const normalizedNodes = (contextJson.nodes || []).map(normalizeNode)
  const elements = buildCytoscapeElements(normalizedNodes, contextJson.edges || [])

  graph.cy.add(elements)

  const templates = [entityTpl, domainClusterTpl, clusterTpl, stepTpl, actionTpl]
  const htmlLabels = HTML_LABEL_CONFIG.map((cfg, i) => ({ ...cfg, tpl: templates[i] }))
  graph.setupHtmlLabels(htmlLabels)

  buildCanvasOverlays(container, normalizedNodes)

  graph.normalizedNodes = new Map(normalizedNodes.map(n => [n.id, n]))

  graph.onNodeClick = (nodeId, nodeData) => {
    container.dispatchEvent(new CustomEvent('foundry:node-selected', {
      detail: { id: nodeId, data: nodeData },
      bubbles: true,
    }))
  }

  graph._runLayout()
  graph.onReady()

  return graph
}
