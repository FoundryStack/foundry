import { _resolveColor, _resolveBg } from '../css_utils.js'
import { getActionTypeColor as getSemanticActionTypeColor, getTypeColor as getSemanticTypeColor } from './semantics.js'

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
    sidebarPu: _resolveColor('--pu'),
    step: _resolveColor('--fg-step'),
    cy:   _resolveColor('--fg-cy'),
    pk:   _resolveColor('--fg-pk'),
    or:   _resolveColor('--fg-or'),
    page: _resolveColor('--fg-page'),
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
  if (c >= 80) return _resolveColor('--fg-gn')
  if (c >= 50) return _resolveColor('--fg-yw')
  return _resolveColor('--fg-rd')
}

export function getTypeColor(type) {
  return toRgbColor(getSemanticTypeColor(type))
}

export function getActionTypeColor(actionType) {
  return toRgbColor(getSemanticActionTypeColor(actionType))
}

export function domainCoverage(nodes) {
  const byDomain = {}
  nodes
    .filter(n => n.nodeKind === 'entity' || (n.nodeKind === 'cluster' && !String(n.id || '').startsWith('domain:')))
    .forEach(n => {
    if (!byDomain[n.domain]) byDomain[n.domain] = []
    byDomain[n.domain].push(n.cov)
  })

  return Object.entries(byDomain).map(([domain, covs]) => {
    const avg = Math.round(covs.reduce((a, c) => a + c, 0) / covs.length)
    return { domain, avg, color: covColor(avg) }
  })
}
