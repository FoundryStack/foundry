import { _resolveColor, _resolveBg } from '../css_utils'

export function extractColors() {
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
    cy:   _resolveColor('--fg-cy'),
    pk:   _resolveColor('--fg-pk'),
    or:   _resolveColor('--fg-or'),
    ac:   _resolveColor('--fg-ac'),
    edgeSequence:     _resolveColor('--fg-edge-sequence'),
    edgeTrigger:      _resolveColor('--fg-edge-trigger'),
    edgeWrite:        _resolveColor('--fg-edge-write'),
    edgeRead:         _resolveColor('--fg-edge-read'),
    edgeGuard:        _resolveColor('--fg-edge-guard'),
    edgeEligible:     _resolveColor('--fg-edge-eligible'),
    edgeAsync:        _resolveColor('--fg-edge-async'),
    edgeEnqueue:      _resolveColor('--fg-edge-enqueue'),
    edgeCompensation: _resolveColor('--fg-edge-compensation'),
    edgeReference:    _resolveColor('--fg-edge-reference'),
    edgeReferencedBy: _resolveColor('--fg-edge-referenced-by'),
    edgeConfigure:    _resolveColor('--fg-edge-configure'),
    edgeAuth:         _resolveColor('--fg-edge-auth'),
    edgePersist:      _resolveColor('--fg-edge-persist'),
    edgeQueue:        _resolveColor('--fg-edge-queue'),
    edgeAdapter:      _resolveColor('--fg-edge-adapter'),
  }
}

function hashString(value) {
  let hash = 0
  for (let i = 0; i < value.length; i++) {
    hash = ((hash << 5) - hash) + value.charCodeAt(i)
    hash |= 0
  }
  return Math.abs(hash)
}

function hslToRgb(h, s, l) {
  const sat = s / 100
  const light = l / 100
  const chroma = (1 - Math.abs((2 * light) - 1)) * sat
  const segment = h / 60
  const x = chroma * (1 - Math.abs((segment % 2) - 1))

  let red = 0
  let green = 0
  let blue = 0

  if (segment >= 0 && segment < 1) [red, green, blue] = [chroma, x, 0]
  else if (segment < 2) [red, green, blue] = [x, chroma, 0]
  else if (segment < 3) [red, green, blue] = [0, chroma, x]
  else if (segment < 4) [red, green, blue] = [0, x, chroma]
  else if (segment < 5) [red, green, blue] = [x, 0, chroma]
  else [red, green, blue] = [chroma, 0, x]

  const match = light - (chroma / 2)
  const r = Math.round((red + match) * 255)
  const g = Math.round((green + match) * 255)
  const b = Math.round((blue + match) * 255)

  return `rgb(${r},${g},${b})`
}

export function withAlpha(color, alpha) {
  const resolved = color.startsWith('var(')
    ? _resolveColor(color.slice(4, -1).trim())
    : color
  const match = resolved.match(/\d+(?:\.\d+)?/g)
  if (!match || match.length < 3) return color
  const [r, g, b] = match.slice(0, 3).map(Number)
  return `rgba(${r},${g},${b},${alpha})`
}

export function toRgbColor(color) {
  const resolved = color.startsWith('var(')
    ? _resolveColor(color.slice(4, -1).trim())
    : color
  const match = resolved.match(/\d+(?:\.\d+)?/g)
  if (!match || match.length < 3) return color
  const [r, g, b] = match.slice(0, 3).map(Number)
  return `rgb(${r},${g},${b})`
}

export function getDomainColor(domain) {
  const hash = hashString(domain || '')
  const hue = (hash * 137.508) % 360
  const saturation = 62 + (hash % 10)
  const lightness = 58 + ((Math.floor(hash / 11)) % 8)
  return hslToRgb(hue, saturation, lightness)
}

export function covColor(c) {
  if (c >= 80) return 'var(--fg-gn)'
  if (c >= 50) return 'var(--fg-yw)'
  return 'var(--fg-rd)'
}

export const TYPE_ICON = {
  resource: '⬡',
  transfer: '⇄',
  rule: '◆',
  reactor: '◈',
  job: '↯',
  liveview: '▣',
  trigger: '▶',
  output: '⟐',
  liveresource: '⊞',
  adapter: '⬚',
  step: '⇄',
  state: '○',
  action: '◆',
  agent: '⊕',
  external: '↗',
  cluster: '◇',
}

export const TYPE_COLOR = {
  resource: 'var(--fg-bl)',
  transfer: 'var(--fg-gn)',
  rule: 'var(--fg-yw)',
  reactor: 'var(--fg-pu)',
  job: 'var(--fg-or)',
  liveview: 'var(--fg-cy)',
  trigger: 'var(--fg-ac)',
  output: 'var(--fg-t2)',
  liveresource: 'var(--fg-pu)',
  adapter: 'var(--fg-ac)',
  step: 'var(--fg-gn)',
  state: 'var(--fg-bl)',
  action: 'var(--fg-gn)',
  agent: 'var(--fg-pu)',
  external: 'var(--fg-t3)',
  cluster: 'var(--fg-t2)',
  domain: 'var(--fg-b2)',
}

const ACTION_TYPE_COLOR = {
  read: 'var(--fg-bl)',
  create: 'var(--fg-gn)',
  update: 'var(--fg-gn)',
  destroy: 'var(--fg-rd)',
}

export function getTypeIcon(type) {
  return TYPE_ICON[type] || TYPE_ICON.resource
}

export function getTypeColor(type) {
  return TYPE_COLOR[type] || 'var(--fg-t2)'
}

export function getActionTypeColor(actionType) {
  return ACTION_TYPE_COLOR[actionType] || TYPE_COLOR.action
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

const NODE_KIND_LABELS = {
  resource: 'Resource',
  transfer: 'Transfer',
  reactor: 'Reactor',
  rule: 'Rule',
  job: 'Job',
  liveview: 'LiveView',
  liveresource: 'LiveResource',
  output: 'Output',
  adapter: 'Adapter',
  external: 'External',
  trigger: 'Trigger',
  agent: 'Agent',
}

const CLUSTER_KIND_LABELS = {
  resource: 'Resource cluster',
  transfer: 'Transfer cluster',
  reactor: 'Reactor cluster',
  fsm: 'FSM cluster',
}

export const NODE_KIND_LEGEND = Object.entries(NODE_KIND_LABELS).map(([type, label]) => ({
  type,
  label,
  icon: TYPE_ICON[type] || TYPE_ICON.resource,
  color: TYPE_COLOR[type] || 'var(--fg-t2)',
}))

export const CLUSTER_KIND_LEGEND = [
  {
    type: 'resource',
    label: CLUSTER_KIND_LABELS.resource,
    color: TYPE_COLOR.resource,
    detail: 'Compound resource boundary.',
  },
  {
    type: 'transfer',
    label: CLUSTER_KIND_LABELS.transfer,
    color: TYPE_COLOR.transfer,
    detail: 'Transfer / saga compound boundary.',
  },
  {
    type: 'reactor',
    label: CLUSTER_KIND_LABELS.reactor,
    color: TYPE_COLOR.reactor,
    detail: 'Reactor compound boundary.',
  },
  {
    type: 'fsm',
    label: CLUSTER_KIND_LABELS.fsm,
    color: TYPE_COLOR.cluster,
    detail: 'State machine compound boundary.',
  },
]

export const STATUS_ICON_LEGEND = [
  { key: 'covered', label: 'Coverage >= 80%', title: 'Test coverage is above 80%.' },
  { key: 'compliance_gap', label: 'Compliance coverage gap', title: 'Declared compliance links do not have linked E2E coverage.' },
  { key: 'sensitive', label: 'Sensitive resource', title: 'Sensitive data or regulated resource.' },
  { key: 'paper_trail', label: 'Paper Trail', title: 'Paper trail change history is enabled.' },
  { key: 'archival', label: 'Archival', title: 'Soft delete / archival is enabled.' },
  { key: 'pm', label: 'Pending migrations', title: 'One or more migrations are pending.' },
  { key: 'oban', label: 'Oban queues', title: 'Oban queues or scheduled jobs are present.' },
  { key: 'schedule', label: 'Schedule', title: 'A scheduled job or trigger is declared.' },
  { key: 'rl', label: 'Rate limited', title: 'Rate limiting is declared.' },
  { key: 'fsm', label: 'State machine', title: 'A finite state machine is present.' },
  { key: 'runbook', label: 'Runbook', title: 'A runbook is linked.' },
]
