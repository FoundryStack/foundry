import { CytoscapeGraph } from './cytoscape_graph'

// Node type → style mapping
const NODE_TYPE_STYLES = {
  resource:     { icon: '⬡', cssVar: '--color-info',      shape: 'diamond' },
  transfer:     { icon: '⇄', cssVar: '--color-accent',    shape: 'pentagon' },
  reactor:      { icon: '◈', cssVar: '--color-accent',    shape: 'hexagon' },
  rule:         { icon: '◆', cssVar: '--color-warning',   shape: 'square' },
  job:          { icon: '⚡', cssVar: '--color-neutral',   shape: 'triangle' },
  liveview:     { icon: '▣', cssVar: '--color-success',   shape: 'vee' },
  liveresource: { icon: '⊞', cssVar: '--color-success',   shape: 'rectangle' },
  blueprint:    { icon: '◇', cssVar: '--color-success',   shape: 'diamond' },
  provider:     { icon: '⬚', cssVar: '--color-secondary', shape: 'square' },
  trigger:      { icon: '▶', cssVar: '--color-warning',   shape: 'triangle' },
  terminal:     { icon: '⟐', cssVar: '--color-error',     shape: 'star' }
}

// Edge relation → style mapping
const EDGE_RELATION_STYLES = {
  triggers:      { style: 'solid',  arrow: 'triangle', cssVar: '--color-info' },
  sequence:      { style: 'solid',  arrow: 'triangle', cssVar: '--color-info' },
  async:         { style: 'dashed', arrow: 'triangle', cssVar: '--color-accent' },
  message:       { style: 'dashed', arrow: 'triangle', cssVar: '--color-accent' },
  guards:        { style: 'dotted', arrow: 'triangle', cssVar: '--color-primary' },
  compensation:  { style: 'dashed', arrow: 'triangle', cssVar: '--color-warning' },
  reads:         { style: 'solid',  arrow: 'diamond',  cssVar: '--color-primary' },
  writes:        { style: 'solid',  arrow: 'diamond',  cssVar: '--color-error' },
  renders:       { style: 'solid',  arrow: 'circle',   cssVar: '--color-success' },
  configured_by: { style: 'solid',  arrow: 'vee',      cssVar: '--color-neutral' }
}

/**
 * Factory function: creates and configures a CytoscapeGraph with Foundry-specific styling
 */
export function mountFoundryGraph(container, contextJson) {
  const graph = new CytoscapeGraph(container)

  const styles = [
    ...graph.cy.style().json(),
    ..._baseColorStyles(),
    ..._generateNodeStyles(),
    ..._generateEdgeStyles()
  ]

  graph.cy.style(styles)
  graph.load(contextJson)

  graph.onNodeClick = (nodeId, nodeData) => {
    container.dispatchEvent(new CustomEvent('foundry:node-selected', {
      detail: { id: nodeId, data: nodeData },
      bubbles: true
    }))
  }

  return graph
}

/**
 * Computes HTML badge row for node indicators
 */
export function computeIndicators(node) {
  const badges = []

  // Compliance + test coverage indicators
  if (node.compliance && node.compliance.length > 0) {
    if (node.test_coverage && node.test_coverage.e2e_tests === true) {
      badges.push('◉') // All covered
    } else {
      badges.push('○') // Gap
    }
  }

  // Rules indicator
  if (node.rules && node.rules.length > 0) {
    badges.push('⬡')
  }

  // PSE badges (sensitive)
  if (node.sensitive === true) {
    const pseBadges = []
    if (node.paper_trail === true) pseBadges.push('P')
    if (node.archival === true) pseBadges.push('S')
    if (node.data_layer === 'ash_postgres') pseBadges.push('E')

    if (pseBadges.length > 0) {
      badges.push(pseBadges.join(''))
    }
  }

  // Runbook indicator
  if (node.runbook !== null && node.runbook !== undefined) {
    badges.push('~')
  }

  // ADRs indicator
  if (node.adrs && node.adrs.length > 0) {
    badges.push('📖')
  }

  // Pending migrations indicator
  if (node.pending_migrations === true) {
    badges.push('↻')
  }

  // Return HTML badge row
  return `<div class="foundry-badges">${badges.join(' ')}</div>`
}

/**
 * Returns edge style for a given edge
 */
export function edgeStyle(edge) {
  const colorMap = {
    '--color-info':      '#06b6d4',
    '--color-accent':    '#a78bfa',
    '--color-warning':   '#f59e0b',
    '--color-neutral':   '#6b7280',
    '--color-success':   '#10b981',
    '--color-secondary': '#64748b',
    '--color-error':     '#ef4444',
    '--color-primary':   '#3b82f6'
  }

  const relationStyle = EDGE_RELATION_STYLES[edge.relation] || EDGE_RELATION_STYLES.reads
  const color = colorMap[relationStyle.cssVar] || '#000'

  return {
    selector: `edge[relation="${edge.relation}"]`,
    style: {
      'line-style': relationStyle.style,
      'target-arrow-shape': relationStyle.arrow,
      'line-color': color,
      'target-arrow-color': color
    }
  }
}

/**
 * Search match function
 */
export function searchMatch(node, query) {
  const queryLower = query.toLowerCase()
  const id = (node.id || '').toLowerCase()
  const type = (node.type || '').toLowerCase()
  const domain = (node.domain || '').toLowerCase()
  const description = (node.description || '').toLowerCase()

  return (
    id.includes(queryLower) ||
    type.includes(queryLower) ||
    domain.includes(queryLower) ||
    description.includes(queryLower)
  )
}

function _baseColorStyles() {
  return [
    {
      selector: 'node',
      style: {
        'background-color': '#d1d5db',
        'color':            '#1f2937'
      }
    },
    {
      selector: 'node.domain-node',
      style: {
        'background-color': '#e5e7eb',
        'border-color':     '#d1d5db'
      }
    },
    {
      selector: 'node.phantom-node',
      style: { 'border-color': '#f59e0b' }
    },
    {
      selector: 'edge',
      style: {
        'line-color':         '#d1d5db',
        'target-arrow-color': '#d1d5db'
      }
    },
    {
      selector: 'edge.phantom-edge',
      style: {
        'line-color':         '#f59e0b',
        'target-arrow-color': '#f59e0b'
      }
    },
    {
      selector: 'node:selected',
      style: { 'border-color': '#0ea5e9' }
    }
  ]
}

function _generateNodeStyles() {
  // Color map: CSS variable name → hex fallback
  const colorMap = {
    '--color-info':      '#06b6d4',
    '--color-accent':    '#a78bfa',
    '--color-warning':   '#f59e0b',
    '--color-neutral':   '#6b7280',
    '--color-success':   '#10b981',
    '--color-secondary': '#64748b',
    '--color-error':     '#ef4444',
    '--color-primary':   '#3b82f6'
  }

  return Object.entries(NODE_TYPE_STYLES).map(([type, s]) => ({
    selector: `node[type="${type}"]`,
    style: {
      'background-color': colorMap[s.cssVar] || '#000',
      'color': '#f3f4f6',
      'shape': s.shape
    }
  }))
}

function _generateEdgeStyles() {
  // Color map: CSS variable name → hex fallback
  const colorMap = {
    '--color-info':      '#06b6d4',
    '--color-accent':    '#a78bfa',
    '--color-warning':   '#f59e0b',
    '--color-neutral':   '#6b7280',
    '--color-success':   '#10b981',
    '--color-secondary': '#64748b',
    '--color-error':     '#ef4444',
    '--color-primary':   '#3b82f6'
  }

  return Object.entries(EDGE_RELATION_STYLES).map(([relation, s]) => ({
    selector: `edge[relation="${relation}"]`,
    style: {
      'line-style': s.style,
      'target-arrow-shape': s.arrow,
      'line-color':         colorMap[s.cssVar] || '#000',
      'target-arrow-color': colorMap[s.cssVar] || '#000',
      'width': 2,
      'curve-style': 'bezier'
    }
  }))
}
