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
    ac:   _resolveColor('--fg-ac'),
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
