import { CytoscapeGraph } from './cytoscape_graph'

/**
 * Convert oklch(L C H) or oklch(L C H / alpha) to hex
 * Handles both oklch(0-1 scale) and oklch(0-100% scale) formats
 */
function _oklchToHex(oklchStr) {
  // Parse oklch(L C H / A) or oklch(L C H) - with or without % sign
  const match = oklchStr.match(/oklch\(([\d.]+)%?\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+))?\)/)
  if (!match) return null

  const [, L, C, H] = match  // A (alpha) not used - oklch colors already in stylesheet
  let l = parseFloat(L)
  // If L > 1, it's in 0-100% format; convert to 0-1
  if (l > 1) l = l / 100
  const c = parseFloat(C)
  const h = parseFloat(H) * Math.PI / 180  // Convert degrees to radians

  // OKLch to linear RGB conversion (via intermediate OKLab)
  const a = c * Math.cos(h)
  const b = c * Math.sin(h)

  // OKLab to linear RGB
  const L_ = l + 0.3963377774 * a + 0.2158037573 * b
  const M_ = l - 0.1055613458 * a - 0.0638541728 * b
  const S_ = l - 0.0894841775 * a - 1.2914855480 * b

  const L_3 = L_ * L_ * L_
  const M_3 = M_ * M_ * M_
  const S_3 = S_ * S_ * S_

  const r = 4.0767416621 * L_3 - 3.3077363322 * M_3 + 0.2309101289 * S_3
  const g = -1.2684380046 * L_3 + 2.6097574011 * M_3 - 0.3413193761 * S_3
  const b_ = -0.0041960863 * L_3 - 0.7034186147 * M_3 + 1.7076147010 * S_3

  // Linear RGB to sRGB (apply gamma)
  const toSRGB = (x) => {
    const abs = Math.abs(x)
    return x >= 0
      ? (abs <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(abs, 1 / 2.4) - 0.055)
      : -(abs <= 0.0031308 ? 12.92 * abs : 1.055 * Math.pow(abs, 1 / 2.4) - 0.055)
  }

  const sr = Math.max(0, Math.min(1, toSRGB(r)))
  const sg = Math.max(0, Math.min(1, toSRGB(g)))
  const sb = Math.max(0, Math.min(1, toSRGB(b_)))

  // Convert to 0-255 range
  const ir = Math.round(sr * 255)
  const ig = Math.round(sg * 255)
  const ib = Math.round(sb * 255)

  // Convert to hex
  const hex = `#${ir.toString(16).padStart(2, '0')}${ig.toString(16).padStart(2, '0')}${ib.toString(16).padStart(2, '0')}`
  return hex
}

/**
 * Convert color-mix(in oklch, colorA alpha%, colorB) with transparent to hex
 * Handles color-mix opacity blending
 */
function _colorMixToHex(colorMixStr) {
  // Parse color-mix(in oklch, var(...) X%, transparent)
  const colorVarMatch = colorMixStr.match(/color-mix\([^,]*,\s*var\(([^)]+)\)\s+([\d.]+)%/)
  if (!colorVarMatch) return null

  const [, varName, opacity] = colorVarMatch
  const opacityPercent = parseFloat(opacity) / 100

  // Extract the variable value from document root
  const rootEl = document.documentElement
  const varValue = getComputedStyle(rootEl).getPropertyValue(varName).trim()

  // Convert the variable value to hex (could be oklch or other format)
  let baseHex = _oklchToHex(varValue)
  if (!baseHex) return null

  // Apply opacity by converting hex to RGB with alpha
  const r = parseInt(baseHex.slice(1, 3), 16)
  const g = parseInt(baseHex.slice(3, 5), 16)
  const b = parseInt(baseHex.slice(5, 7), 16)

  // Blend with white based on opacity (simulating color-mix with transparent)
  const blendWithWhite = (channel) => Math.round(channel * opacityPercent + 255 * (1 - opacityPercent))

  const blendedR = blendWithWhite(r)
  const blendedG = blendWithWhite(g)
  const blendedB = blendWithWhite(b)

  return `#${blendedR.toString(16).padStart(2, '0')}${blendedG.toString(16).padStart(2, '0')}${blendedB.toString(16).padStart(2, '0')}`
}

/**
 * Extract CSS custom properties from document root and compute them to hex
 * Called once at mount, result cached for use in Cytoscape stylesheet
 */
function _extractColors() {
  const tok = (varName) => {
    const rootEl = document.documentElement
    const computed = getComputedStyle(rootEl).getPropertyValue(varName).trim()

    // Try oklch conversion
    const oklchHex = _oklchToHex(computed)
    if (oklchHex) return oklchHex

    // Try color-mix conversion
    const colorMixHex = _colorMixToHex(computed)
    if (colorMixHex) return colorMixHex

    // Try hex format (simple colors like --fg-bl, --fg-gn, etc.)
    if (computed.match(/^#[0-9a-f]{6}$/i)) return computed

    // Fallback: try to convert via temporary element
    const el = document.createElement('div')
    el.style.backgroundColor = `var(${varName})`
    document.body.appendChild(el)
    const bgColor = getComputedStyle(el).backgroundColor
    document.body.removeChild(el)

    const rgbMatch = bgColor.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/)
    if (rgbMatch) {
      const r = parseInt(rgbMatch[1]).toString(16).padStart(2, '0')
      const g = parseInt(rgbMatch[2]).toString(16).padStart(2, '0')
      const b = parseInt(rgbMatch[3]).toString(16).padStart(2, '0')
      return `#${r}${g}${b}`
    }

    console.warn(`Could not convert color variable ${varName}=${computed}`)
    return '#000000'  // Safe fallback to black
  }

  return {
    base: tok('--fg-base'),
    tx: tok('--fg-tx'),
    t2: tok('--fg-t2'),
    t3: tok('--fg-t3'),
    s2: tok('--fg-s2'),
    s3: tok('--fg-s3'),
    b1: tok('--fg-b1'),
    b2: tok('--fg-b2'),
    b3: tok('--fg-b3'),
    bl: tok('--fg-bl'),
    gn: tok('--fg-gn'),
    yw: tok('--fg-yw'),
    rd: tok('--fg-rd'),
    pu: tok('--fg-pu'),
    ac: tok('--fg-ac')
    // Note: --fg-r is a radius value, not a color - excluded from color extraction
  }
}

/**
 * Normalize Elixir NodeEntry → GraphNode field mapping
 */
export function normalizeNode(raw) {
  const tc = raw.test_coverage || {}
  const sm = raw.state_machine || {}

  // Derive coverage % from 3 boolean flags
  const cov = (tc.property_tests ? 33 : 0) + (tc.scenario_tests ? 33 : 0) + (tc.e2e_tests ? 34 : 0)

  // Gap = has compliance reqs but no E2E tests
  const reqs = raw.compliance || []
  const gap = reqs.length > 0 && !tc.e2e_tests

  // State machine: synthesize IDs as "${nodeId}:state:${stateName}"
  const states = (sm.states || []).map(name => ({
    id: `${raw.id}:state:${name}`,
    name,
    nodeKind: 'state'
  }))
  const smTransitions = sm.transitions || []

  // Merge agent steps via step_id lookup
  const steps = (raw.steps || []).map(s => ({
    ...s,
    agent: (raw.agent_steps || []).find(a => a.step_id === s.id)
  }))

  // Description fallback: if no description, use "type in domain"
  const description = raw.description || (raw.type && raw.domain ? `${raw.type} in ${raw.domain}` : raw.type || 'No description')

  return {
    id: raw.id,
    type: raw.type,
    domain: raw.domain,
    description,
    nodeKind: 'entity',
    cov,
    reqs,
    gap,
    sensitive: raw.sensitive,
    pt: raw.paper_trail,
    arch: raw.archival,
    dl: raw.data_layer,
    rl: raw.rate_limited,
    sm: states.length > 0 ? { states, transitions: smTransitions } : null,
    steps,
    routes: raw.api_routes || [],
    money: raw.money_attributes || [],
    flags: raw.feature_flags || [],
    runbook: raw.runbook,
    adrs: raw.adrs || [],
    pending_migrations: raw.pending_migrations,
    last_modified: raw.last_modified,
    schedule: raw.schedule || null,
    oban_queues: raw.oban_queues || [],
    performs: raw.performs || null,
    // Keep original for any missing fields
    ...raw
  }
}

/**
 * Get compound node IDs: transfers, reactors + FSM resources
 */
export function getCompoundNodeIds(nodes) {
  const transfers = nodes.filter(n => n.type === 'transfer' || n.type === 'reactor').map(n => n.id)
  const fsms = nodes.filter(n => n.type === 'resource' && n.sm).map(n => n.id)
  return new Set([...transfers, ...fsms])
}

/**
 * Get transfer/reactor node IDs (nodes that have steps)
 */
export function getTransferNodeIds(nodes) {
  return new Set(nodes.filter(n => n.type === 'transfer' || n.type === 'reactor').map(n => n.id))
}

/**
 * Get FSM resource IDs
 */
export function getFsmResourceIds(nodes) {
  return new Set(nodes.filter(n => n.type === 'resource' && n.sm).map(n => n.id))
}

/**
 * Strip app prefix and return short label
 * "IgamingRef.Finance.Wallet" → "Wallet"
 * "external:postgres:Finance" → "postgres:Finance"
 */
export function shortLabel(id) {
  if (!id) return id
  // Don't strip external node prefixes, just the module FQN
  if (id.startsWith('external:')) {
    return id.replace('external:', '')
  }
  const parts = id.split('.')
  return parts[parts.length - 1]
}

/**
 * Build indicator span HTML
 */
export function buildIndicators(n) {
  const indicators = []

  // Coverage indicator
  if (n.cov >= 80) {
    indicators.push(`<span data-indicator="covered" title="Test coverage ≥80%">✓</span>`)
  } else if (n.gap) {
    indicators.push(`<span data-indicator="gap" title="Compliance gap">⊘</span>`)
  }

  // Sensitive indicators
  if (n.sensitive) {
    if (n.pt) indicators.push(`<span data-indicator="paper_trail" title="Paper Trail">≣</span>`)
    if (n.arch) indicators.push(`<span data-indicator="archival" title="Archival">⊟</span>`)
  }

  // Pending migrations
  if (n.pending_migrations) {
    indicators.push(`<span data-indicator="pm" title="Pending migrations">↻</span>`)
  }

  // Oban queue / job schedule
  if ((n.oban_queues || []).length > 0) {
    indicators.push(`<span data-indicator="oban" title="Oban queues">⚙</span>`)
  }
  if (n.schedule) {
    indicators.push(`<span data-indicator="schedule" title="Schedule: ${n.schedule}">⏱</span>`)
  }

  // Rate limiting
  if (n.rl) {
    indicators.push(`<span data-indicator="rl" title="Rate limited">⬅</span>`)
  }

  // FSM
  if (n.sm && n.sm.states) {
    indicators.push(`<span data-indicator="fsm" title="State machine">◊</span>`)
  }

  // Runbook
  if (n.runbook) {
    indicators.push(`<span data-indicator="runbook" title="Runbook">📖</span>`)
  }

  return `<div class="status-icons">${indicators.join('')}</div>`
}

/**
 * Coverage color → CSS var
 */
export function covColor(c) {
  if (c >= 80) return 'var(--fg-gn)'
  if (c >= 50) return 'var(--fg-yw)'
  return 'var(--fg-rd)'
}

/**
 * Domain color mapping - distinct colors for each domain
 */
const DOMAIN_COLORS = {
  'Finance': '#60a5fa',      // blue
  'Players': '#34d399',      // green
  'Promotions': '#f59e0b',   // amber
  'Gaming': '#a78bfa',       // purple
  'Accounts': '#06b6d4',     // cyan
  'Infrastructure': '#6b7280' // gray
}

export function getDomainColor(domain) {
  // Return specific color if defined, or generate a stable color based on domain hash
  if (DOMAIN_COLORS[domain]) return DOMAIN_COLORS[domain]

  // Fallback: generate stable color from domain name hash
  let hash = 0
  for (let i = 0; i < domain.length; i++) {
    hash = ((hash << 5) - hash) + domain.charCodeAt(i)
    hash = hash & hash // Convert to 32bit integer
  }

  const colors = Object.values(DOMAIN_COLORS)
  return colors[Math.abs(hash) % colors.length]
}

/**
 * Domain coverage by type
 */
export function domainCoverage(nodes) {
  const byDomain = {}
  nodes.forEach(n => {
    if (!byDomain[n.domain]) {
      byDomain[n.domain] = []
    }
    byDomain[n.domain].push(n.cov)
  })

  return Object.entries(byDomain).map(([domain, covs]) => {
    const avg = Math.round(covs.reduce((a, c) => a + c, 0) / covs.length)
    return { domain, avg, color: covColor(avg) }
  })
}

/**
 * Entity node HTML template
 */
export function entityTpl(data) {
  const n = data
  const indicators = buildIndicators(n)
  const classes = n.type === 'external' ? 'cy-external-node' : ''

  // For external nodes, show simpler layout
  if (n.type === 'external') {
    return `
      <div class="cy-node-html ${classes}">
        <span class="title">${shortLabel(n.id)}</span>
      </div>
    `
  }

  const jobAnnotation = n.type === 'job' && (n.oban_queues?.length > 0 || n.schedule)
    ? `<div style="font-size:9px;color:var(--fg-pu);margin-top:1px">⚙ ${n.oban_queues?.[0] || 'default'}${n.schedule ? ' · ' + n.schedule : ''}</div>`
    : ''

  return `
    <div class="cy-node-html">
      ${indicators}
      <div class="domain-row">
        <span class="domain-dot" style="background: ${covColor(n.cov)}"></span>
        <span style="color: var(--fg-t2)">${n.domain || 'N/A'}</span>
      </div>
      <div class="title-row">
        <span class="type-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <circle cx="12" cy="12" r="10"></circle>
          </svg>
        </span>
        <span class="title">${shortLabel(n.id)}</span>
      </div>
      ${jobAnnotation}
      ${n.cov > 0 ? `
        <div class="req-badges">
          <div style="width:${n.cov}%; height:3px; background:${covColor(n.cov)}; border-radius:1px"></div>
        </div>
      ` : ''}
    </div>
  `
}

/**
 * Domain cluster HTML template
 */
export function domainClusterTpl(data) {
  const n = data
  return `
    <div class="cy-node-html cy-domain-cluster">
      <span class="domain-cluster-label" style="color:${n.typeColor}">${n.label}</span>
    </div>
  `
}

/**
 * Unified cluster template that handles both domain and transfer/reactor clusters
 */
export function clusterTpl(data) {
  const n = data

  // Domain cluster: show prominent domain label
  if (n.nodeKind === 'domain-cluster') {
    return `
      <div class="cy-node-html cy-domain-cluster">
        <span class="domain-cluster-label" style="color:${n.typeColor}">${n.label}</span>
      </div>
    `
  }

  // Transfer/reactor/FSM cluster: show with icon
  let icon = '◈'
  let label = shortLabel(n.id)

  if (n.type === 'transfer') {
    icon = '⇄'
  } else if (n.type === 'reactor') {
    icon = '◈'
  } else if (n.type === 'job') {
    icon = '⚙'
  } else if (n.type === 'blueprint') {
    icon = '◇'
  } else if (n.sm) {
    icon = '◊'
  }

  return `
    <div class="cy-node-html cy-node-boundary">
      <div class="domain-row">
        <span class="domain-dot" style="background: var(--fg-yw)"></span>
        <span style="color: var(--fg-t2)">${icon} ${label}</span>
      </div>
    </div>
  `
}

/**
 * Boundary (cluster) node HTML template - DEPRECATED, use clusterTpl instead
 */
export function boundaryTpl(data) {
  return clusterTpl(data)
}

/**
 * Build canvas overlays: grid, gradient, edge legend, domain coverage
 */
export function buildCanvasOverlays(container, nodes) {
  const overlays = document.createElement('div')
  overlays.id = 'foundry-canvas-overlays'
  overlays.style.cssText = `
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
    z-index: 1;
  `

  // Domain coverage header (top-left, clickable)
  const coverage = domainCoverage(nodes)
  const coverageHtml = coverage
    .map(
      ({ domain, avg }) =>
        `<span style="color:${covColor(avg)}; margin-right:12px">${domain} ${avg}%</span>`
    )
    .join('')

  const header = document.createElement('div')
  header.style.cssText = `
    position: absolute;
    top: 8px;
    left: 8px;
    padding: 8px 12px;
    background: rgba(30,30,45,0.8);
    border: 1px solid var(--fg-b1);
    border-radius: 4px;
    font-size: 11px;
    color: var(--fg-t2);
  `
  header.innerHTML = coverageHtml
  overlays.appendChild(header)

  container.parentElement.appendChild(overlays)
}

/**
 * Consolidate fragmented external nodes.
 * e.g. "external:postgres:Finance" + "external:postgres:Players" → single "external:postgres"
 * Returns { nodes: dedupedNodes, edgeMap: { originalId → collapsedId } }
 */
export function consolidateExternalNodes(nodes) {
  const edgeMap = {}
  const seen = new Set()
  const result = []

  for (const n of nodes) {
    if (n.type === 'external') {
      // Pattern: external:<provider>:<suffix> → collapse to external:<provider>
      const match = n.id.match(/^(external:[^:]+):/)
      if (match) {
        const collapsedId = match[1]
        edgeMap[n.id] = collapsedId
        if (!seen.has(collapsedId)) {
          seen.add(collapsedId)
          result.push({ ...n, id: collapsedId, label: collapsedId.replace('external:', '') })
        }
        continue
      }
    }
    result.push(n)
  }

  return { nodes: result, edgeMap }
}

/**
 * Build Cytoscape elements from normalized nodes/edges
 */
export function buildCytoscapeElements(nodes, edges) {
  const elements = []

  // Consolidate fragmented external nodes (e.g. external:postgres:Finance → external:postgres)
  const { nodes: consolidatedNodes, edgeMap: externalEdgeMap } = consolidateExternalNodes(nodes)
  nodes = consolidatedNodes

  // Create domain cluster compounds (one per unique domain)
  const domains = new Set(nodes.map(n => n.domain).filter(Boolean))
  domains.forEach(domain => {
    const domainColor = getDomainColor(domain)
    elements.push({
      group: 'nodes',
      data: {
        id: `domain:${domain}`,
        label: domain,
        nodeKind: 'cluster',
        domain,
        typeColor: domainColor
      },
      classes: 'domain-cluster'
    })
  })

  // Get compound node IDs
  const compoundIds = getCompoundNodeIds(nodes)

  // Create transfer/FSM compound nodes
  compoundIds.forEach(id => {
    const node = nodes.find(n => n.id === id)
    if (!node) return
    const label = shortLabel(id)
    elements.push({
      group: 'nodes',
      data: {
        id: `compound:${id}`,
        label,
        nodeKind: 'cluster',
        type: node.type,
        parent: node.domain ? `domain:${node.domain}` : null
      },
      classes: 'transfer-cluster fsm-cluster'
    })
  })

  // Create entity nodes
  nodes.forEach(node => {
    // Determine parent: either domain cluster or transfer/FSM compound
    const parent = compoundIds.has(node.id)
      ? `compound:${node.id}`
      : (node.domain ? `domain:${node.domain}` : null)

    const classes = []
    if (node.gap) classes.push('gap')
    if (node.sensitive) classes.push('sensitive')

    elements.push({
      group: 'nodes',
      data: {
        id: node.id,
        nodeKind: 'entity',
        parent,
        ...node
      },
      classes: classes.join(' ')
    })
  })

  // Add step/state child nodes for transfers, reactors and FSMs
  nodes.forEach(node => {
    // Transfer/reactor steps
    if ((node.type === 'transfer' || node.type === 'reactor') && node.steps) {
      node.steps.forEach((step, idx) => {
        // Normalize step_kind (remove atom prefix if present)
        const stepKind = (step.step_kind || '').toString().replace(/^:/, '')

        // Build step label with kind icon
        let stepIcon = '⚙'
        if (stepKind === 'read') {
          stepIcon = '📖'
        } else if (stepKind === 'write') {
          stepIcon = '✏'
        } else if (stepKind === 'map') {
          stepIcon = '◈'
        }
        const stepLabel = `${stepIcon} ${step.name || `Step ${idx}`}`

        elements.push({
          group: 'nodes',
          data: {
            id: `${node.id}:step:${idx}`,
            label: stepLabel,
            nodeKind: 'step',
            parent: `compound:${node.id}`,
            step_kind: stepKind,
            description: step.description || step.name || `Step ${idx}`,
            type: node.type,
            domain: node.domain
          }
        })
      })

      // Add sequence edges between steps
      if (node.steps && node.steps.length > 1) {
        node.steps.forEach((step, idx) => {
          if (idx > 0) {
            elements.push({
              group: 'edges',
              data: {
                id: `${node.id}:seq:${idx}`,
                source: `${node.id}:step:${idx - 1}`,
                target: `${node.id}:step:${idx}`,
                relation: 'sequence'
              }
            })
          }
        })
      }

      // Guard edges: rule node → specific step (cross-compound, shows which rules each step uses)
      node.steps.forEach((step, idx) => {
        const stepNodeId = `${node.id}:step:${idx}`
        const rulesApplied = step.rules_applied || []
        rulesApplied.forEach(ruleId => {
          elements.push({
            group: 'edges',
            data: {
              id: `${ruleId}->guard->${stepNodeId}`,
              source: ruleId,
              target: stepNodeId,
              relation: 'guard'
            }
          })
        })
      })
    }

    // FSM states
    if (node.sm && node.sm.states) {
      node.sm.states.forEach(state => {
        elements.push({
          group: 'nodes',
          data: {
            id: state.id,
            label: state.name,
            nodeKind: 'state',
            parent: `compound:${node.id}`
          }
        })
      })
    }
  })

  // Create edges — remap external node IDs through consolidation map
  edges.forEach(edge => {
    const source = externalEdgeMap[edge.from] || edge.from
    const target = externalEdgeMap[edge.to] || edge.to

    // Skip self-edges that arise from consolidation (e.g. two postgres:X → postgres edges merged)
    if (source === target) return

    elements.push({
      group: 'edges',
      data: {
        id: `${source}->${target}:${edge.relation}`,
        source,
        target,
        relation: edge.relation,
        ...edge,
        from: source,
        to: target
      }
    })
  })

  return elements
}

/**
 * Factory function: creates and configures a CytoscapeGraph with Foundry-specific styling
 */
export function mountFoundryGraph(container, contextJson) {
  // Extract colors from CSS once
  const colors = _extractColors()

  // Create graph with color injection
  const graph = new CytoscapeGraph(container, {}, colors)

  // Normalize all nodes
  const normalizedNodes = (contextJson.nodes || []).map(normalizeNode)

  // Build Cytoscape elements
  const elements = buildCytoscapeElements(normalizedNodes, contextJson.edges || [])

  // Load elements into graph
  graph.cy.add(elements)

  // Set up HTML labels
  graph.setupHtmlLabels(entityTpl, boundaryTpl, domainClusterTpl, stepTpl)

  // Build canvas overlays
  buildCanvasOverlays(container, normalizedNodes)

  // Attach normalized nodes map for hook use
  graph.normalizedNodes = new Map(normalizedNodes.map(n => [n.id, n]))

  // Wire up click handler
  graph.onNodeClick = (nodeId, nodeData) => {
    container.dispatchEvent(new CustomEvent('foundry:node-selected', {
      detail: { id: nodeId, data: nodeData },
      bubbles: true
    }))
  }

  // Run layout
  graph._runLayout()
  graph.onReady()

  return graph
}

/**
 * HTML label template for step nodes
 */
export function stepTpl(data) {
  const n = data
  const icons = { read: '📖', write: '✏', map: '◈', custom: '⚙' }
  const icon = icons[n.step_kind] || '⚙'
  return `<div class="cy-node-html cy-step-node" style="text-align:center;font-size:9px;line-height:1.2;padding:2px 4px">
    <span>${icon}</span><br>
    <span style="color:var(--fg-tx)">${n.label || n.id}</span>
  </div>`
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

