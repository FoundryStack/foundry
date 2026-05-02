export const NODE_KIND_META = {
  resource: {
    label: 'Resource',
    tooltipLabel: 'resource',
    icon: '⬡',
    color: 'var(--fg-bl)',
    colorToken: 'bl',
  },
  transfer: {
    label: 'Transfer',
    tooltipLabel: 'transfer',
    icon: '⇄',
    color: 'var(--fg-gn)',
    colorToken: 'gn',
  },
  rule: {
    label: 'Rule',
    tooltipLabel: 'rule',
    icon: '◆',
    color: 'var(--fg-yw)',
    colorToken: 'yw',
  },
  reactor: {
    label: 'Reactor',
    tooltipLabel: 'reactor',
    icon: '◈',
    color: 'var(--fg-pu)',
    colorToken: 'pu',
  },
  job: {
    label: 'Job',
    tooltipLabel: 'job',
    icon: '↯',
    color: 'var(--fg-or)',
    colorToken: 'or',
  },
  liveview: {
    label: 'LiveView',
    tooltipLabel: 'liveview',
    icon: '▣',
    color: 'var(--fg-cy)',
    colorToken: 'cy',
  },
  trigger: {
    label: 'Trigger',
    tooltipLabel: 'trigger',
    icon: '▶',
    color: 'var(--fg-ac)',
    colorToken: 'ac',
  },
  output: {
    label: 'Output',
    tooltipLabel: 'output',
    icon: '⟐',
    color: 'var(--fg-t2)',
    colorToken: 't2',
  },
  liveresource: {
    label: 'LiveResource',
    tooltipLabel: 'liveresource',
    icon: '⊞',
    color: 'var(--fg-pk)',
    colorToken: 'pk',
  },
  blueprint: {
    label: 'Blueprint (legacy)',
    tooltipLabel: 'blueprint',
    icon: '◇',
    color: 'var(--fg-or)',
    colorToken: 'or',
  },
  adapter: {
    label: 'Adapter',
    tooltipLabel: 'adapter',
    icon: '⬚',
    color: 'var(--fg-ac)',
    colorToken: 'ac',
  },
  step: {
    label: 'Step',
    tooltipLabel: 'step',
    icon: '⇄',
    color: 'var(--fg-gn)',
    colorToken: 'gn',
  },
  state: {
    label: 'State',
    tooltipLabel: 'state',
    icon: '○',
    color: 'var(--fg-bl)',
    colorToken: 'bl',
  },
  action: {
    label: 'Action',
    tooltipLabel: 'action',
    icon: '◆',
    color: 'var(--fg-gn)',
    colorToken: 'gn',
  },
  agent: {
    label: 'Agent Step',
    tooltipLabel: 'agent step',
    icon: '⊕',
    color: 'var(--fg-pu)',
    colorToken: 'pu',
  },
  external: {
    label: 'External',
    tooltipLabel: 'external',
    icon: '↗',
    color: 'var(--fg-t3)',
    colorToken: 't3',
  },
  cluster: {
    label: 'Boundary',
    tooltipLabel: 'boundary',
    icon: '◇',
    color: 'var(--fg-t2)',
    colorToken: 't2',
  },
}

export const ACTION_TYPE_COLOR = {
  read: 'var(--fg-bl)',
  create: 'var(--fg-gn)',
  update: 'var(--fg-gn)',
  destroy: 'var(--fg-rd)',
}

export const LEGEND_SECTION_LABELS = {
  nodeKinds: 'Node Kinds',
  boundaryKinds: 'Boundaries',
  statusIcons: 'Status Icons',
  edgeTypes: 'Edge Types',
}

export const BOUNDARY_KIND_LEGEND = [
  {
    type: 'domain',
    label: 'Domain group',
    color: 'var(--fg-b2)',
    detail: 'Top-level Ash domain grouping. Border color varies by domain.',
  },
  {
    type: 'resource',
    label: 'Resource boundary',
    color: NODE_KIND_META.resource.color,
    detail: 'Compound resource boundary.',
  },
  {
    type: 'transfer',
    label: 'Transfer boundary',
    color: NODE_KIND_META.transfer.color,
    detail: 'Transfer / saga compound boundary.',
  },
  {
    type: 'reactor',
    label: 'Reactor boundary',
    color: NODE_KIND_META.reactor.color,
    detail: 'Reactor compound boundary.',
  },
  {
    type: 'fsm',
    label: 'FSM boundary',
    color: NODE_KIND_META.cluster.color,
    detail: 'State machine compound boundary.',
  },
]

export const STATUS_META = {
  covered: {
    label: 'Coverage >= 80%',
    title: 'Test coverage is above 80%.',
  },
  compliance_gap: {
    label: 'Compliance coverage gap',
    title: 'Declared compliance links do not have linked E2E coverage.',
  },
  sensitive: {
    label: 'Sensitive resource',
    title: 'Sensitive data or regulated resource.',
  },
  paper_trail: {
    label: 'Paper Trail',
    title: 'Paper trail change history is enabled.',
  },
  archival: {
    label: 'Archival',
    title: 'Soft delete / archival is enabled.',
  },
  pm: {
    label: 'Pending migrations',
    title: 'One or more migrations are pending.',
  },
  oban: {
    label: 'Oban queues',
    title: 'Oban queues or scheduled jobs are present.',
  },
  schedule: {
    label: 'Schedule',
    title: 'A scheduled job or trigger is declared.',
  },
  rl: {
    label: 'Rate limited',
    title: 'Rate limiting is declared.',
  },
  fsm: {
    label: 'State machine',
    title: 'A finite state machine is present.',
  },
  runbook: {
    label: 'Runbook',
    title: 'A runbook is linked.',
  },
}

const NODE_KIND_LEGEND_ORDER = [
  'resource',
  'transfer',
  'reactor',
  'rule',
  'job',
  'liveview',
  'liveresource',
  'adapter',
  'external',
  'trigger',
  'blueprint',
  'agent',
  'step',
  'action',
  'state',
  'output',
]

const GOVERNANCE_NODE_KINDS = new Set(['entity', 'cluster'])

export function normalizeGraphNodeType(type) {
  return type === 'provider' ? 'adapter' : type
}

export function getNodeKindMeta(type) {
  return NODE_KIND_META[normalizeGraphNodeType(type)] || NODE_KIND_META.resource
}

export function getTypeIcon(type) {
  return getNodeKindMeta(type).icon
}

export function getTypeColor(type) {
  return getNodeKindMeta(type).color
}

export function getTypeColorToken(type) {
  return getNodeKindMeta(type).colorToken || 't2'
}

export function getActionTypeColor(actionType) {
  return ACTION_TYPE_COLOR[actionType] || NODE_KIND_META.action.color
}

export function getNodeKindLegend() {
  return NODE_KIND_LEGEND_ORDER.map(type => {
    const meta = getNodeKindMeta(type)
    return {
      type,
      label: meta.label,
      icon: meta.icon,
      color: meta.color,
    }
  })
}

export function getBoundaryKindLegend() {
  return BOUNDARY_KIND_LEGEND
}

export function getStatusLegend() {
  return Object.entries(STATUS_META).map(([key, value]) => ({ key, ...value }))
}

export function isDomainClusterNode(node) {
  return node?.nodeKind === 'cluster' &&
    typeof node?.id === 'string' &&
    node.id.startsWith('domain:')
}

export function getTypeDisplayLabel(nodeOrType) {
  if (typeof nodeOrType === 'string') {
    return getNodeKindMeta(nodeOrType).tooltipLabel || nodeOrType
  }

  if (isDomainClusterNode(nodeOrType)) {
    return 'domain'
  }

  const type = normalizeGraphNodeType(nodeOrType?.type || nodeOrType?.nodeKind || 'resource')
  return getNodeKindMeta(type).tooltipLabel || type
}

export function computeCoverageScore(testCoverage = {}) {
  return (testCoverage.property_tests ? 33 : 0) +
    (testCoverage.scenario_tests ? 33 : 0) +
    (testCoverage.e2e_tests ? 34 : 0)
}

export function getComplianceStatus(compliance = [], testCoverage = {}) {
  const requirements = Array.isArray(compliance) ? compliance : []
  const hasLinks = requirements.length > 0
  const hasGap = hasLinks && !testCoverage.e2e_tests

  return {
    hasLinks,
    hasGap,
    key: hasGap ? 'compliance_gap' : 'covered',
    label: hasGap ? 'coverage gap' : 'covered',
  }
}

export function canShowGovernanceIndicators(node) {
  return GOVERNANCE_NODE_KINDS.has(node?.nodeKind || 'entity')
}

export function shouldShowComplianceIndicator(node) {
  if (!canShowGovernanceIndicators(node)) return false
  if (typeof node?.has_compliance_links === 'boolean') return node.has_compliance_links
  return Array.isArray(node?.reqs) && node.reqs.length > 0
}

export function shouldShowComplianceGap(node) {
  return shouldShowComplianceIndicator(node) && !!(node?.compliance_gap ?? node?.gap)
}

export function shouldShowCoverageIndicator(node) {
  return canShowGovernanceIndicators(node) &&
    !shouldShowComplianceGap(node) &&
    (node?.cov || 0) >= 80
}
