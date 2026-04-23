const FONT = 'Segoe UI Symbol, Apple Symbols, Arial Unicode MS, sans-serif'

export const FOUNDRY_LAYOUT_OPTIONS = {
  randomize: false,
  idealEdgeLength: 62,
  nodeRepulsion: 4200,
  padding: 32,
  gravity: 0.35,
  gravityCompound: 1.25,
  nestingFactor: 0.18,
}

export const FOUNDRY_COMPOUND_COMPACTION = {
  enabled: true,
  selector: 'node.domain-cluster, node.transfer-cluster, node.fsm-cluster',
  maxChildren: 5,
  minOccupancy: 0.32,
  spacing: 44,
  padding: 30,
}

export const STATIC_STYLES = [
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
  {
    selector: 'node[nodeKind="entity"], node[nodeKind="step"], node[nodeKind="action"], node[nodeKind="state"], node[nodeKind="output"], node[nodeKind="cluster"]',
    style: { 'label': '' },
  },
  {
    selector: 'node.gap',
    style: { 'border-width': 1, 'border-style': 'dashed' },
  },
  {
    selector: 'node[nodeKind="cluster"]',
    style: {
      'shape': 'round-rectangle',
      'min-width': 120,
      'min-height': 60,
      'padding': 28,
      'border-style': 'dashed',
      'text-valign': 'center',
      'text-halign': 'center',
    },
  },
  {
    selector: 'node.domain-cluster',
    style: { 'border-width': 2, 'background-opacity': 0.4, 'padding': 20 },
  },
  {
    selector: 'node[nodeKind="step"], node[nodeKind="action"], node[nodeKind="state"]',
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
  {
    selector: 'node[nodeKind="action"]',
    style: { 'width': 98, 'height': 40 },
  },
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
  {
    selector: 'node:selected',
    style: { 'border-width': 1.5 },
  },
  {
    selector: 'node.phantom-node',
    style: {
      'border-width': 2,
      'border-style': 'dashed',
      'opacity': 0.5,
      'background-opacity': 0.5,
    },
  },
  {
    selector: 'node[type="external"]',
    style: { 'border-style': 'dashed', 'border-width': 1, 'opacity': 0.7 },
  },
  {
    selector: 'node[type="job"]',
    style: { 'border-style': 'dashed', 'border-width': 1.5 },
  },
  {
    selector: 'node[type="trigger"]',
    style: { 'shape': 'barrel', 'border-style': 'dotted', 'border-width': 1.5 },
  },
  {
    selector: 'node[type="blueprint"]',
    style: { 'shape': 'diamond', 'width': 110, 'height': 66, 'border-width': 1 },
  },
  {
    selector: 'node[nodeKind="cluster"][type="transfer"], node[nodeKind="cluster"][type="reactor"]',
    style: { 'border-width': 1.5 },
  },
  {
    selector: 'edge',
    style: {
      'width': 1.5,
      'target-arrow-shape': 'triangle',
      'curve-style': 'bezier',
      'opacity': 0.8,
    },
  },
  {
    selector: 'edge[relation="reads"]',
    style: { 'target-arrow-shape': 'diamond', 'target-arrow-fill': 'hollow' },
  },
  {
    selector: 'edge[relation="writes"]',
    style: { 'target-arrow-shape': 'diamond', 'target-arrow-fill': 'filled' },
  },
  {
    selector: 'edge[relation="triggers"]',
    style: { 'target-arrow-shape': 'circle', 'target-arrow-fill': 'filled' },
  },
  {
    selector: 'edge[relation="guard"], edge[relation="eligibleIf"], edge[relation="guards"]',
    style: { 'line-style': 'dotted', 'width': 1.2 },
  },
  {
    selector: 'edge[relation="async"]',
    style: { 'line-style': 'dashed' },
  },
  {
    selector: 'edge[relation="error"]',
    style: { 'line-style': 'dashed' },
  },
  {
    selector: 'edge[relation="compensation"]',
    style: { 'width': 2 },
  },
  {
    selector: 'edge[relation="references"]',
    style: { 'target-arrow-shape': 'triangle', 'line-style': 'solid' },
  },
  {
    selector: 'edge[relation="referenced_by"]',
    style: { 'target-arrow-shape': 'triangle', 'line-style': 'solid' },
  },
  {
    selector: 'edge[relation="configures"]',
    style: { 'line-style': 'dashed', 'width': 1.5, 'opacity': 0.8 },
  },
  {
    selector: 'edge[relation="authenticates"]',
    style: { 'line-style': 'dashed', 'width': 1.8 },
  },
  {
    selector: 'edge[relation="persists_to"]',
    style: { 'line-style': 'dotted', 'width': 1 },
  },
  {
    selector: 'edge[relation="queues_via"]',
    style: { 'line-style': 'dotted', 'width': 1 },
  },
  {
    selector: 'edge[relation="calls_provider"]',
    style: { 'line-style': 'dotted', 'width': 1.5 },
  },
  {
    selector: 'edge[relation="audit_trail"]',
    style: {
      'line-style': 'dotted',
      'target-arrow-shape': 'triangle',
      'opacity': 0.4,
      'width': 1,
    },
  },
  {
    selector: 'edge:compound',
    style: {
      'source-endpoint': 'outside-to-node',
      'target-endpoint': 'outside-to-node',
    },
  },
  {
    selector: '.trace, .trace-gap',
    style: { 'border-width': 1 },
  },
  {
    selector: 'node[nodeKind="step"][has_declared_se="true"]',
    style: { 'border-style': 'solid', 'border-width': 1.5 },
  },
  {
    selector: 'node[nodeKind="step"][has_inferred_se="true"]',
    style: { 'border-style': 'dashed', 'border-width': 1.5 },
  },
]

export function dynamicStyles(c) {
  const domainColorToken = {
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

  const stepColorToken = {
    read:   'bl',
    write:  'gn',
    map:    'pu',
    custom: 't2',
  }

  const actionColorToken = {
    read: 'bl',
    create: 'gn',
    update: 'gn',
    destroy: 'rd',
  }

  const domainSelectors = Object.entries(domainColorToken).map(([domain, token]) => ({
    selector: `node[domain="${domain}"]`,
    style: { 'border-color': c[token] },
  }))

  const stepKindSelectors = Object.entries(stepColorToken).map(([kind, token]) => ({
    selector: `node[nodeKind="step"][step_kind="${kind}"]`,
    style: { 'background-color': c[token], 'border-color': c[token] },
  }))

  const actionTypeSelectors = Object.entries(actionColorToken).map(([kind, token]) => ({
    selector: `node[nodeKind="action"][action_type="${kind}"]`,
    style: { 'background-color': c[token], 'border-color': c[token] },
  }))

  return [
    {
      selector: 'node',
      style: {
        'background-color': c.nodeBg,
        'border-color': c.b1,
        'color': c.tx,
      },
    },
    { selector: 'node.gap',       style: { 'border-color': c.yw } },
    { selector: 'node.sensitive', style: { 'border-width': 1, 'border-color': c.rd } },
    {
      selector: 'node[nodeKind="cluster"]',
      style: {
        'background-color': c.clusterBg,
        'border-color': c.b1,
      },
    },
    {
      selector: 'node.domain-cluster',
      style: { 'background-color': c.clusterBg },
    },
    ...domainSelectors,
    { selector: 'node:selected', style: { 'border-color': c.ac } },
    {
      selector: 'node[type="external"]',
      style: { 'background-color': c.s3, 'border-color': c.t3 },
    },
    { selector: 'node[nodeKind="step"], node[nodeKind="action"]', style: { 'color': c.tx } },
    ...stepKindSelectors,
    ...actionTypeSelectors,
    { selector: 'node[type="job"]',       style: { 'border-color': c.pu } },
    { selector: 'node[type="trigger"]',   style: { 'border-color': c.ac } },
    { selector: 'node[type="blueprint"]', style: { 'border-color': c.ac } },
    {
      selector: 'node[nodeKind="cluster"][type="transfer"]',
      style: { 'border-color': c.gn },
    },
    {
      selector: 'node[nodeKind="cluster"][type="reactor"]',
      style: { 'border-color': c.pu },
    },
    { selector: 'node[nodeKind="step"][has_declared_se="true"]',
      style: { 'border-color': c.gn } },
    { selector: 'node[nodeKind="step"][has_inferred_se="true"]',
      style: { 'border-color': c.rd } },
    {
      selector: 'edge',
      style: { 'line-color': c.t2, 'target-arrow-color': c.t2 },
    },
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
    { selector: '.trace, .trace-gap', style: { 'border-color': c.yw } },
  ]
}

export function buildFoundryStyles(colors) {
  return [...STATIC_STYLES, ...dynamicStyles(colors)]
}
