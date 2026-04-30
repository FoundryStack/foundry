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
    edgeProvider:     _resolveColor('--fg-edge-provider'),
  }
}

const DOMAIN_COLOR_TOKENS = ['bl', 'gn', 'yw', 'pu', 't2', 'rd', 'ac', 'b1', 'b2', 'b3']

export function getDomainColor(domain) {
  let hash = 0
  for (let i = 0; i < domain.length; i++) {
    hash = ((hash << 5) - hash) + domain.charCodeAt(i)
    hash = hash & hash
  }
  const token = DOMAIN_COLOR_TOKENS[Math.abs(hash) % DOMAIN_COLOR_TOKENS.length]
  return `var(--fg-${token})`
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
  blueprint: '◇',
  liveresource: '⊞',
  provider: '⬚',
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
  job: 'var(--fg-yw)',
  liveview: 'var(--fg-bl)',
  trigger: 'var(--fg-ac)',
  output: 'var(--fg-t2)',
  blueprint: 'var(--fg-pu)',
  liveresource: 'var(--fg-pu)',
  provider: 'var(--fg-yw)',
  step: 'var(--fg-gn)',
  state: 'var(--fg-bl)',
  action: 'var(--fg-gn)',
  agent: 'var(--fg-pu)',
  external: 'var(--fg-t3)',
  cluster: 'var(--fg-t2)',
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
