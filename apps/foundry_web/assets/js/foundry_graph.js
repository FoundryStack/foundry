import { CytoscapeGraph } from './cytoscape_graph'
import { _probe, _resolveColor, _resolveBg } from './css_utils'

/**
 * Read all Foundry theme tokens from CSS into a plain object of resolved rgb()
 * strings. Called once at mount and again whenever data-theme changes.
 * Properties suffixed with `Bg` use _resolveBg(); text-color properties use _resolveColor().
 */
function _extractColors() {
  return {
    nodeBg:    _resolveBg('--graph-node-bg'),
    clusterBg: _resolveBg('--graph-cluster-bg'),
    base: _resolveBg('--fg-base'),
    s2:   _resolveBg('--fg-s2'),
    s3:   _resolveBg('--fg-s3'),
    tx:   _resolveColor('--fg-tx'),
    t2:   _resolveColor('--fg-t2'),
    t3:   _resolveColor('--fg-t3'),
    b1:   _resolveColor('--fg-b1'),
    b2:   _resolveColor('--fg-b2'),
    b3:   _resolveColor('--fg-b3'),
    bl:   _resolveColor('--fg-bl'),
    gn:   _resolveColor('--fg-gn'),
    yw:   _resolveColor('--fg-yw'),
    rd:   _resolveColor('--fg-rd'),
    pu:   _resolveColor('--fg-pu'),
    ac:   _resolveColor('--fg-ac'),
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Foundry stylesheet
//
// Split into two layers:
//   STATIC_STYLES  — geometry, shape, layout props. Never depend on theme.
//                    Defined once as a module-level constant.
//   _dynamicStyles — only the ~15 selectors that carry color values.
//                    Rebuilt on mount and on every theme change.
//
// The full stylesheet passed to Cytoscape is [...STATIC_STYLES, ..._dynamicStyles(c)].
// ─────────────────────────────────────────────────────────────────────────────

const FONT = "'Segoe UI Symbol', 'Apple Symbols', 'Arial Unicode MS', sans-serif"

const STATIC_STYLES = [
  // Base node geometry
  {
    selector: 'node',
    style: {
      'shape': 'round-rectangle',
      'width': 170,
      'height': 64,
      'border-width': 1,
      'border-style': 'solid',
      'border-opacity': 1,
      'font-size': 11,
      'font-family': FONT,
      'text-valign': 'center',
      'text-halign': 'center',
      'text-margin-x': 0,
      'text-margin-y': 0,
      'text-wrap': 'none',
      'padding': 6,
      'label': 'data(label)',
    },
  },
  // Hide Cytoscape's native label for nodes that use HTML labels
  {
    selector: 'node[nodeKind="entity"], node[nodeKind="step"], node[nodeKind="state"], node[nodeKind="output"], node[nodeKind="cluster"]',
    style: { 'label': '' },
  },
  // Compliance gap: dashed border (color applied in dynamic styles)
  {
    selector: 'node.gap',
    style: { 'border-width': 1, 'border-style': 'dashed' },
  },
  // Cluster / compound base geometry
  {
    selector: 'node[nodeKind="cluster"]',
    style: {
      'shape': 'round-rectangle',
      'min-width': 120,
      'min-height': 60,
      'padding': 32,
      'border-style': 'dashed',
      'text-valign': 'center',
      'text-halign': 'center',
    },
  },
  // Domain cluster geometry
  {
    selector: 'node.domain-cluster',
    style: { 'border-width': 2, 'background-opacity': 0.4, 'padding': 24 },
  },
  // Step / state node geometry
  {
    selector: 'node[nodeKind="step"], node[nodeKind="state"]',
    style: {
      'width': 88,
      'height': 40,
      'font-size': 9,
      'font-family': FONT,
      'text-valign': 'center',
      'text-halign': 'center',
      'text-wrap': 'none',
    },
  },
  // Step nodes: text color from theme
  {
    selector: 'node[nodeKind="step"]',
    style: { 'color': 'var(--fg-tx)' },
  },
  // Output node geometry
  {
    selector: 'node[nodeKind="output"]',
    style: {
      'width': 76,
      'height': 36,
      'font-size': 8,
      'font-family': FONT,
      'text-valign': 'center',
      'text-halign': 'center',
      'text-wrap': 'none',
    },
  },
  // Selection ring geometry (color in dynamic styles)
  {
    selector: 'node:selected',
    style: { 'border-width': 1.5 },
  },
  // Phantom / proposal overlay
  {
    selector: 'node.phantom-node',
    style: {
      'border-width': 2,
      'border-style': 'dashed',
      'opacity': 0.5,
      'background-opacity': 0.5,
    },
  },
  // External node geometry
  {
    selector: 'node[type="external"]',
    style: { 'border-style': 'dashed', 'border-width': 1, 'opacity': 0.7 },
  },
  // Job node: dashed border signals async/scheduled nature
  {
    selector: 'node[type="job"]',
    style: { 'border-style': 'dashed', 'border-width': 1.5 },
  },
  // Trigger node: inbox/chevron shape signals entry point (HTTP endpoint or webhook)
  {
    selector: 'node[type="trigger"]',
    style: { 'shape': 'barrel', 'border-style': 'dotted', 'border-width': 1.5 },
  },
  // Blueprint node: diamond shape
  {
    selector: 'node[type="blueprint"]',
    style: { 'shape': 'diamond', 'width': 110, 'height': 66, 'border-width': 1 },
  },
  // Transfer / reactor compound cluster border width
  {
    selector: 'node[nodeKind="cluster"][type="transfer"], node[nodeKind="cluster"][type="reactor"]',
    style: { 'border-width': 1.5 },
  },
  // Edge base geometry
  {
    selector: 'edge',
    style: {
      'width': 1.5,
      'target-arrow-shape': 'triangle',
      'curve-style': 'bezier',
      'opacity': 0.8,
    },
  },
  // Relation: reads — hollow diamond
  {
    selector: 'edge[relation="reads"]',
    style: { 'target-arrow-shape': 'diamond', 'target-arrow-fill': 'hollow' },
  },
  // Relation: writes — filled diamond
  {
    selector: 'edge[relation="writes"]',
    style: { 'target-arrow-shape': 'diamond', 'target-arrow-fill': 'filled' },
  },
  // Relation: triggers — filled circle
  {
    selector: 'edge[relation="triggers"]',
    style: { 'target-arrow-shape': 'circle', 'target-arrow-fill': 'filled' },
  },
  // Relation: guard / eligibleIf / guards — dotted, narrower
  {
    selector: 'edge[relation="guard"], edge[relation="eligibleIf"], edge[relation="guards"]',
    style: { 'line-style': 'dotted', 'width': 1.2 },
  },
  // Relation: async — dashed
  {
    selector: 'edge[relation="async"]',
    style: { 'line-style': 'dashed' },
  },
  // Relation: error — dashed
  {
    selector: 'edge[relation="error"]',
    style: { 'line-style': 'dashed' },
  },
  // Relation: compensation — wider
  {
    selector: 'edge[relation="compensation"]',
    style: { 'width': 2 },
  },
  // Relation: references — solid triangle
  {
    selector: 'edge[relation="references"]',
    style: { 'target-arrow-shape': 'triangle', 'line-style': 'solid' },
  },
  // Relation: referenced_by — solid triangle
  {
    selector: 'edge[relation="referenced_by"]',
    style: { 'target-arrow-shape': 'triangle', 'line-style': 'solid' },
  },
  // Relation: configures — dashed
  {
    selector: 'edge[relation="configures"]',
    style: { 'line-style': 'dashed', 'width': 1.5, 'opacity': 0.8 },
  },
  // Relation: authenticates — dashed, slightly wider
  {
    selector: 'edge[relation="authenticates"]',
    style: { 'line-style': 'dashed', 'width': 1.8 },
  },
  // Relation: persists_to — dotted, thin
  {
    selector: 'edge[relation="persists_to"]',
    style: { 'line-style': 'dotted', 'width': 1 },
  },
  // Relation: queues_via — dotted, thin
  {
    selector: 'edge[relation="queues_via"]',
    style: { 'line-style': 'dotted', 'width': 1 },
  },
  // Relation: calls_provider — dotted
  {
    selector: 'edge[relation="calls_provider"]',
    style: { 'line-style': 'dotted', 'width': 1.5 },
  },
  // Relation: audit_trail — dotted, faded
  {
    selector: 'edge[relation="audit_trail"]',
    style: {
      'line-style': 'dotted',
      'target-arrow-shape': 'triangle',
      'opacity': 0.4,
      'width': 1,
    },
  },
  // Compound edge endpoints
  {
    selector: 'edge:compound',
    style: {
      'source-endpoint': 'outside-to-node',
      'target-endpoint': 'outside-to-node',
    },
  },
  // Trace overlay geometry
  {
    selector: '.trace, .trace-gap',
    style: { 'border-width': 1 },
  },
  // Step nodes with side effects: solid border
  {
    selector: 'node[nodeKind="step"][has_declared_se="true"]',
    style: { 'border-style': 'solid', 'border-width': 1.5 },
  },
  // Step nodes with inferred side effects: dashed border
  {
    selector: 'node[nodeKind="step"][has_inferred_se="true"]',
    style: { 'border-style': 'dashed', 'border-width': 1.5 },
  },
]

// Domain → color token. Key is the domain name, value is a key into the
// colors object returned by _extractColors(). Unknown domains fall back via
// getDomainColor()'s hash-based picker.
const DOMAIN_COLOR_TOKEN = {
  Finance:        'bl',
  Players:        'gn',
  Promotions:     'yw',
  Gaming:         'pu',
  Accounts:       'bl',
  Infrastructure: 't2',
  Identity:       'gn',
  Compliance:     'yw',
  Game:           'pu',
}

// Step kind → color token
const STEP_COLOR_TOKEN = {
  read:   'bl',
  write:  'gn',
  map:    'pu',
  custom: 't2',
}

/**
 * Build the color-dependent portion of the Cytoscape stylesheet.
 * Receives a colors object from _extractColors() — all values are resolved
 * rgb() strings the browser and Cytoscape can both use directly.
 */
function _dynamicStyles(c) {
  // Domain border-color selectors — one per known domain
  const domainSelectors = Object.entries(DOMAIN_COLOR_TOKEN).map(([domain, token]) => ({
    selector: `node[domain="${domain}"]`,
    style: { 'border-color': c[token] },
  }))

  // Step kind background + border — one per step_kind
  const stepKindSelectors = Object.entries(STEP_COLOR_TOKEN).map(([kind, token]) => ({
    selector: `node[nodeKind="step"][step_kind="${kind}"]`,
    style: { 'background-color': c[token], 'border-color': c[token] },
  }))

  return [
    // Base node colors
    {
      selector: 'node',
      style: {
        'background-color': c.nodeBg,
        'border-color': c.b1,
        'color': c.tx,
      },
    },
    // Compliance gap border color
    { selector: 'node.gap',       style: { 'border-color': c.yw } },
    // Sensitive border color
    { selector: 'node.sensitive', style: { 'border-width': 1, 'border-color': c.rd } },
    // Cluster base colors (darker than regular nodes)
    {
      selector: 'node[nodeKind="cluster"]',
      style: {
        'background-color': c.clusterBg,
        'border-color': c.b1,
      },
    },
    // Domain cluster background
    {
      selector: 'node.domain-cluster',
      style: { 'background-color': c.clusterBg },
    },
    // Per-domain border colors
    ...domainSelectors,
    // Selection ring
    { selector: 'node:selected', style: { 'border-color': c.ac } },
    // External node colors
    {
      selector: 'node[type="external"]',
      style: { 'background-color': c.s3, 'border-color': c.t3 },
    },
    // Step kind colors
    ...stepKindSelectors,
    // Job node border
    { selector: 'node[type="job"]',       style: { 'border-color': c.pu } },
    // Trigger node border (webhook, HTTP endpoint)
    { selector: 'node[type="trigger"]',   style: { 'border-color': c.ac } },
    // Blueprint border
    { selector: 'node[type="blueprint"]', style: { 'border-color': c.ac } },
    // Transfer cluster border
    {
      selector: 'node[nodeKind="cluster"][type="transfer"]',
      style: { 'border-color': c.gn },
    },
    // Reactor cluster border
    {
      selector: 'node[nodeKind="cluster"][type="reactor"]',
      style: { 'border-color': c.pu },
    },
    // Step nodes with declared side effects: green border
    { selector: 'node[nodeKind="step"][has_declared_se="true"]',
      style: { 'border-color': c.gn } },
    // Step nodes with inferred side effects: red border
    { selector: 'node[nodeKind="step"][has_inferred_se="true"]',
      style: { 'border-color': c.rd } },
    // Edge base colors
    {
      selector: 'edge',
      style: { 'line-color': c.t2, 'target-arrow-color': c.t2 },
    },
    // Relation colors — only entries that override the base edge color
    { selector: 'edge[relation="sequence"]',
      style: { 'line-color': c.t2, 'target-arrow-color': c.t2 } },
    { selector: 'edge[relation="async"]',
      style: { 'line-color': c.pu, 'target-arrow-color': c.pu } },
    { selector: 'edge[relation="guard"], edge[relation="eligibleIf"], edge[relation="guards"]',
      style: { 'line-color': c.yw, 'target-arrow-color': c.yw } },
    { selector: 'edge[relation="compensation"]',
      style: { 'line-color': c.yw, 'target-arrow-color': c.yw } },
    { selector: 'edge[relation="error"]',
      style: { 'line-color': c.rd, 'target-arrow-color': c.rd } },
    { selector: 'edge[relation="reads"]',
      style: { 'line-color': c.bl, 'target-arrow-color': c.bl } },
    { selector: 'edge[relation="writes"]',
      style: { 'line-color': c.gn, 'target-arrow-color': c.gn } },
    { selector: 'edge[relation="triggers"]',
      style: { 'line-color': c.pu, 'target-arrow-color': c.pu } },
    { selector: 'edge[relation="references"]',
      style: { 'line-color': c.b2, 'target-arrow-color': c.b2 } },
    { selector: 'edge[relation="referenced_by"]',
      style: { 'line-color': c.t2, 'target-arrow-color': c.t2 } },
    { selector: 'edge[relation="configures"]',
      style: { 'line-color': c.ac, 'target-arrow-color': c.ac } },
    { selector: 'edge[relation="authenticates"]',
      style: { 'line-color': c.gn, 'target-arrow-color': c.gn } },
    { selector: 'edge[relation="persists_to"]',
      style: { 'line-color': c.t3, 'target-arrow-color': c.t3 } },
    { selector: 'edge[relation="queues_via"]',
      style: { 'line-color': c.pu, 'target-arrow-color': c.pu } },
    { selector: 'edge[relation="calls_provider"]',
      style: { 'line-color': c.yw, 'target-arrow-color': c.yw } },
    { selector: 'edge[relation="audit_trail"]',
      style: { 'line-color': c.yw, 'target-arrow-color': c.yw } },
    // Trace overlays
    { selector: '.trace, .trace-gap', style: { 'border-color': c.yw } },
  ]
}

/**
 * Full Foundry stylesheet: static geometry + dynamic colors.
 */
function _buildFoundryStyles(colors) {
  return [...STATIC_STYLES, ..._dynamicStyles(colors)]
}

// ─────────────────────────────────────────────────────────────────────────────
// Node normalization
// ─────────────────────────────────────────────────────────────────────────────

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
    nodeKind: 'state',
  }))
  const smTransitions = sm.transitions || []

  // Merge agent steps via step_id lookup
  const steps = (raw.steps || []).map(s => ({
    ...s,
    agent: (raw.agent_steps || []).find(a => a.step_id === s.id),
  }))

  const description = raw.description || (raw.type && raw.domain
    ? `${raw.type} in ${raw.domain}`
    : raw.type || 'No description')

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
    ...raw,
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Graph structure helpers
// ─────────────────────────────────────────────────────────────────────────────

export function getCompoundNodeIds(nodes) {
  const transfers = nodes.filter(n => n.type === 'transfer' || n.type === 'reactor').map(n => n.id)
  const fsms = nodes.filter(n => n.type === 'resource' && n.sm).map(n => n.id)
  return new Set([...transfers, ...fsms])
}

export function getTransferNodeIds(nodes) {
  return new Set(nodes.filter(n => n.type === 'transfer' || n.type === 'reactor').map(n => n.id))
}

export function getFsmResourceIds(nodes) {
  return new Set(nodes.filter(n => n.type === 'resource' && n.sm).map(n => n.id))
}

/**
 * Strip app prefix and return short label.
 * "IgamingRef.Finance.Wallet" → "Wallet"
 * "external:postgres:Finance" → "postgres:Finance"
 */
export function shortLabel(id) {
  if (!id) return id
  if (id.startsWith('external:')) return id.replace('external:', '')
  const parts = id.split('.')
  return parts[parts.length - 1]
}

// ─────────────────────────────────────────────────────────────────────────────
// Domain colors
// ─────────────────────────────────────────────────────────────────────────────

// Hardcoded hex values mirror the dark-theme --fg-* defaults.
// These are used for HTML label coloring (domainClusterTpl) where CSS vars
// work fine. The Cytoscape stylesheet uses _extractColors() tokens instead.
const DOMAIN_COLORS = {
  Finance:        'var(--fg-bl)',
  Players:        'var(--fg-gn)',
  Promotions:     'var(--fg-yw)',
  Gaming:         'var(--fg-pu)',
  Accounts:       'var(--fg-bl)',
  Infrastructure: 'var(--fg-t2)',
  Identity:       'var(--fg-gn)',
  Compliance:     'var(--fg-yw)',
  Game:           'var(--fg-pu)',
}

export function getDomainColor(domain) {
  if (DOMAIN_COLORS[domain]) return DOMAIN_COLORS[domain]

  // Stable hash-based fallback for unknown domains
  let hash = 0
  for (let i = 0; i < domain.length; i++) {
    hash = ((hash << 5) - hash) + domain.charCodeAt(i)
    hash = hash & hash
  }
  const colors = Object.values(DOMAIN_COLORS)
  return colors[Math.abs(hash) % colors.length]
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility functions
// ─────────────────────────────────────────────────────────────────────────────

export function covColor(c) {
  if (c >= 80) return 'var(--fg-gn)'
  if (c >= 50) return 'var(--fg-yw)'
  return 'var(--fg-rd)'
}

export function domainCoverage(nodes) {
  const byDomain = {}
  nodes.forEach(n => {
    if (!byDomain[n.domain]) byDomain[n.domain] = []
    byDomain[n.domain].push(n.cov)
  })

  return Object.entries(byDomain).map(([domain, covs]) => {
    const avg = Math.round(covs.reduce((a, c) => a + c, 0) / covs.length)
    return { domain, avg, color: covColor(avg) }
  })
}

/**
 * Search match — used by callers to build the matchingIds set passed to
 * graph.applySearchFilter(). Kept here because it knows Foundry's data fields.
 */
export function searchMatch(node, query) {
  const q = query.toLowerCase()
  return (
    (node.id          || '').toLowerCase().includes(q) ||
    (node.type        || '').toLowerCase().includes(q) ||
    (node.domain      || '').toLowerCase().includes(q) ||
    (node.description || '').toLowerCase().includes(q)
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// HTML label templates
// ─────────────────────────────────────────────────────────────────────────────

export function buildIndicators(n) {
  const indicators = []

  if (n.cov >= 80) {
    indicators.push(`<span data-indicator="covered" title="Test coverage ≥80%">✓</span>`)
  } else if (n.gap) {
    indicators.push(`<span data-indicator="gap" title="Compliance gap">⊘</span>`)
  }

  if (n.sensitive) {
    indicators.push(`<span data-indicator="sensitive" title="Sensitive data">⚠</span>`)
  }

  if (n.pt || n.arch) {
    if (n.pt)   indicators.push(`<span data-indicator="paper_trail" title="Paper Trail">≣</span>`)
    if (n.arch) indicators.push(`<span data-indicator="archival" title="Archival">⊟</span>`)
  }

  if (n.pending_migrations) {
    indicators.push(`<span data-indicator="pm" title="Pending migrations">↻</span>`)
  }

  if ((n.oban_queues || []).length > 0) {
    indicators.push(`<span data-indicator="oban" title="Oban queues">⚙</span>`)
  }
  if (n.schedule) {
    indicators.push(`<span data-indicator="schedule" title="Schedule: ${n.schedule}">⏱</span>`)
  }

  if (n.rl) {
    indicators.push(`<span data-indicator="rl" title="Rate limited">⬅</span>`)
  }

  if (n.sm?.states) {
    indicators.push(`<span data-indicator="fsm" title="State machine">◊</span>`)
  }

  if (n.runbook) {
    indicators.push(`<span data-indicator="runbook" title="Runbook">📖</span>`)
  }

  return `<div class="status-icons">${indicators.join('')}</div>`
}

export function entityTpl(data) {
  const n = data

  if (n.type === 'external') {
    return `
      <div class="cy-node-html cy-external-node">
        <span class="title">${shortLabel(n.id)}</span>
      </div>
    `
  }

  const jobAnnotation = n.type === 'job' && (n.oban_queues?.length > 0 || n.schedule)
    ? `<div style="font-size:9px;color:var(--fg-pu);margin-top:1px">⚙ ${n.oban_queues?.[0] || 'default'}${n.schedule ? ' · ' + n.schedule : ''}</div>`
    : ''

  // Trigger annotation: show HTTP endpoint or webhook route
  const triggerAnnotation = n.type === 'trigger' && (n.routes?.length > 0)
    ? `<div style="font-size:8px;color:var(--fg-ac);margin-top:2px;font-family:var(--font-mono)">${n.routes[0].r}</div>`
    : ''

  return `
    <div class="cy-node-html">
      ${buildIndicators(n)}
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
      ${triggerAnnotation}
      ${n.cov > 0 ? `
        <div class="req-badges">
          <div style="width:${n.cov}%; height:3px; background:${covColor(n.cov)}; border-radius:1px"></div>
        </div>
      ` : ''}
    </div>
  `
}

export function domainClusterTpl(data) {
  return `
    <div class="cy-node-html cy-domain-cluster">
      <span class="domain-cluster-label" style="color:${data.typeColor}">${data.label}</span>
    </div>
  `
}

export function clusterTpl(data) {
  const n = data
  if (data.nodeKind === 'domain-cluster' || data.classes?.includes('domain-cluster')) return domainClusterTpl(data)

  const icons = { transfer: '⇄', reactor: '◈', job: '⚙', blueprint: '◇' }
  const icon = icons[n.type] || (n.sm ? '◊' : '◈')
  const cov = n.cov ?? 0

  return `
    <div class="cy-node-html cy-node-boundary" style="margin-left: 12px; margin-top: 12px">
      ${buildIndicators(n)}
      <div class="domain-row">
        <span class="domain-dot" style="background: ${covColor(cov)}"></span>
        <span style="color: var(--fg-t2)">${n.domain || ''}</span>
      </div>
      <div class="title-row">
        <span class="type-icon">${icon}</span>
        <span class="title">${shortLabel(n.id)}</span>
      </div>
      ${cov > 0 ? `<div class="req-badges"><div style="width:${cov}%; height:3px; background:${covColor(cov)}; border-radius:1px"></div></div>` : ''}
    </div>
  `
}

/** @deprecated Use clusterTpl instead */
export function boundaryTpl(data) {
  return clusterTpl(data)
}

export function stepTpl(data) {
  const icons = { read: '📖', write: '✏', map: '◈', custom: '⚙' }
  const icon = icons[data.step_kind] || '⚙'
  const ses = data.side_effects || []
  const seBadges = ses.map(se => {
    const color = se.declared ? 'var(--fg-gn)' : 'var(--fg-rd)'
    const prefix = se.declared ? '' : '⚠ '
    return `<span style="display:inline-block;font-size:7px;padding:1px 3px;border-radius:2px;background:${color};color:var(--fg-base);margin:1px">${prefix}${se.type}</span>`
  }).join('')
  return `
    <div class="cy-node-html cy-step-node" style="text-align:center;font-size:9px;line-height:1.2;padding:2px 4px">
      <span>${icon}</span><br>
      <span style="color:var(--fg-tx)">${data.label || data.id}</span>
      ${ses.length > 0 ? `<div style="margin-top:2px">${seBadges}</div>` : ''}
    </div>
  `
}

// ─────────────────────────────────────────────────────────────────────────────
// Element builders
// ─────────────────────────────────────────────────────────────────────────────

export function consolidateExternalNodes(nodes) {
  const edgeMap = {}
  const seen = new Set()
  const result = []

  for (const n of nodes) {
    if (n.type === 'external') {
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

export function buildCytoscapeElements(nodes, edges) {
  const elements = []

  const { nodes: consolidatedNodes, edgeMap: externalEdgeMap } = consolidateExternalNodes(nodes)
  nodes = consolidatedNodes

  // Domain cluster compounds
  const domains = new Set(nodes.map(n => n.domain).filter(Boolean))
  domains.forEach(domain => {
    elements.push({
      group: 'nodes',
      data: {
        id: `domain:${domain}`,
        label: domain,
        nodeKind: 'cluster',
        domain,
        typeColor: getDomainColor(domain),
      },
      classes: 'domain-cluster',
    })
  })

  const compoundIds = getCompoundNodeIds(nodes)

  // Transfer / FSM compound nodes (now IS the entity)
  compoundIds.forEach(id => {
    const node = nodes.find(n => n.id === id)
    if (!node) return
    const classes = [
      node.type === 'transfer' ? 'transfer-cluster' : null,
      node.type === 'reactor' ? 'transfer-cluster' : null,
      node.sm ? 'fsm-cluster' : null,
      node.gap ? 'gap' : null,
      node.sensitive ? 'sensitive' : null,
    ].filter(Boolean).join(' ')

    elements.push({
      group: 'nodes',
      data: {
        ...node,           // all entity data (cov, steps, reqs, etc.)
        id: node.id,       // original ID — edges already use this
        label: shortLabel(node.id),
        nodeKind: 'cluster',
        parent: node.domain ? `domain:${node.domain}` : null,
      },
      classes,
    })
  })

  // Entity nodes — only for non-compound nodes
  nodes.forEach(node => {
    if (compoundIds.has(node.id)) return // already added as compound above

    const parent = node.domain ? `domain:${node.domain}` : null

    const classes = [
      node.gap       ? 'gap'       : null,
      node.sensitive ? 'sensitive' : null,
    ].filter(Boolean).join(' ')

    elements.push({
      group: 'nodes',
      data: { id: node.id, nodeKind: 'entity', parent, ...node },
      classes,
    })
  })

  // Step / state child nodes
  nodes.forEach(node => {
    if ((node.type === 'transfer' || node.type === 'reactor') && node.steps) {
      node.steps.forEach((step, idx) => {
        const stepKind = (step.step_kind || '').toString().replace(/^:/, '')
        const icons = { read: '📖', write: '✏', map: '◈' }
        const stepLabel = `${icons[stepKind] || '⚙'} ${step.name || `Step ${idx}`}`

        const sideEffects = step.side_effects || []
        elements.push({
          group: 'nodes',
          data: {
            id: `${node.id}:step:${idx}`,
            label: stepLabel,
            nodeKind: 'step',
            parent: node.id,
            step_kind: stepKind,
            description: step.description || step.name || `Step ${idx}`,
            type: node.type,
            domain: node.domain,
            side_effects: sideEffects,
            has_declared_se: sideEffects.some(se => se.declared) ? 'true' : 'false',
            has_inferred_se: sideEffects.some(se => !se.declared) ? 'true' : 'false',
          },
        })
      })

      if (node.steps.length > 1) {
        node.steps.forEach((_, idx) => {
          if (idx === 0) return
          elements.push({
            group: 'edges',
            data: {
              id: `${node.id}:seq:${idx}`,
              source: `${node.id}:step:${idx - 1}`,
              target: `${node.id}:step:${idx}`,
              relation: 'sequence',
            },
          })
        })
      }

      node.steps.forEach((step, idx) => {
        const stepNodeId = `${node.id}:step:${idx}`;
        (step.rules_applied || []).forEach(ruleId => {
          elements.push({
            group: 'edges',
            data: {
              id: `${ruleId}->guard->${stepNodeId}`,
              source: ruleId,
              target: stepNodeId,
              relation: 'guard',
            },
          })
        })
      })

    }

    if (node.sm?.states) {
      node.sm.states.forEach(state => {
        elements.push({
          group: 'nodes',
          data: {
            id: state.id,
            label: state.name,
            nodeKind: 'state',
            parent: node.id,
          },
        })
      })
    }
  })

  // Edges
  edges.forEach(edge => {
    const source = externalEdgeMap[edge.from] || edge.from
    const target = externalEdgeMap[edge.to] || edge.to
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
        to: target,
      },
    })
  })

  return elements
}

// ─────────────────────────────────────────────────────────────────────────────
// Canvas overlays
// ─────────────────────────────────────────────────────────────────────────────

export function buildCanvasOverlays(container, nodes) {
  const overlays = document.createElement('div')
  overlays.id = 'foundry-canvas-overlays'
  overlays.style.cssText = `
    position: absolute; top: 0; left: 0;
    width: 100%; height: 100%;
    pointer-events: none; z-index: 1;
  `

  const coverage = domainCoverage(nodes)
  const coverageHtml = coverage
    .map(({ domain, avg }) =>
      `<span style="color:${covColor(avg)};margin-right:12px">${domain} ${avg}%</span>`)
    .join('')

  const header = document.createElement('div')
  header.style.cssText = `
    position: absolute; top: 8px; left: 8px;
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

// ─────────────────────────────────────────────────────────────────────────────
// Mount
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Factory: creates and fully configures a CytoscapeGraph for Foundry.
 * Owns the stylesheet, theme watching, HTML label templates, and event wiring.
 */
export function mountFoundryGraph(container, contextJson) {
  const colors = _extractColors()

  const graph = new CytoscapeGraph(container, {
    style: _buildFoundryStyles(colors),
  })

  // Rebuild only the color-dependent stylesheet slice when the theme changes.
  // STATIC_STYLES never needs to rebuild.
  new MutationObserver(() => {
    graph.cy.style(_buildFoundryStyles(_extractColors())).update()
  }).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['data-theme'],
  })

  const normalizedNodes = (contextJson.nodes || []).map(normalizeNode)
  const elements = buildCytoscapeElements(normalizedNodes, contextJson.edges || [])

  graph.cy.add(elements)

  graph.setupHtmlLabels([
    { query: 'node[nodeKind="entity"]',  halign: 'center', valign: 'center', halignBox: 'center', valignBox: 'center', tpl: entityTpl },
    { query: 'node.domain-cluster',      halign: 'left',   valign: 'top',    halignBox: 'left',   valignBox: 'top',    tpl: domainClusterTpl },
    { query: 'node[nodeKind="cluster"]:not(.domain-cluster)', halign: 'left', valign: 'top', halignBox: 'left', valignBox: 'top', tpl: clusterTpl },
    { query: 'node[nodeKind="step"]',    halign: 'center', valign: 'center', halignBox: 'center', valignBox: 'center', tpl: stepTpl },
  ])

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