import { domainCoverage, covColor, getDomainColor } from './colors'
import { EDGE_CATALOG, edgeLegendDash } from './edge_catalog'

export function searchMatch(node, query) {
  const q = query.toLowerCase()
  return (
    (node.id          || '').toLowerCase().includes(q) ||
    (node.type        || '').toLowerCase().includes(q) ||
    (node.domain      || '').toLowerCase().includes(q) ||
    (node.description || '').toLowerCase().includes(q)
  )
}

export function buildCanvasOverlays(container, nodes) {
  const canvas = container.parentElement
  if (!canvas) return

  canvas.querySelector('#foundry-canvas-overlays')?.remove()

  const overlays = document.createElement('div')
  overlays.id = 'foundry-canvas-overlays'

  const coverage = domainCoverage(nodes)
  const coverageHtml = coverage
    .map(({ domain, avg }) =>
      `<div class="fm-domain-coverage-item">
        <span class="fm-domain-coverage-name" style="color:${getDomainColor(domain)}">${escHtml(domain).toUpperCase()}</span>
        <div class="fm-domain-coverage-bar">
          <div class="fm-domain-coverage-fill" style="width:${avg}%;background:${covColor(avg)}"></div>
        </div>
        <span class="fm-domain-coverage-value" style="color:${covColor(avg)}">${avg}%</span>
      </div>`)
    .join('')

  const header = document.createElement('div')
  header.className = 'fm-domain-coverage'
  header.innerHTML = coverageHtml
  overlays.appendChild(header)

  const legend = document.createElement('div')
  legend.className = 'fm-edge-legend'
  legend.innerHTML = `
    <div class="fm-edge-legend-title">Edge Types</div>
    ${EDGE_CATALOG.map(edge => {
      const dash = edgeLegendDash(edge)
      const dashAttr = dash ? ` stroke-dasharray="${dash}"` : ''
      const opacityAttr = edge.opacity ? ` opacity="${edge.opacity}"` : ''
      const title = `${edge.label}: ${edge.description} Source: ${edge.source}`
      return `
        <div class="fm-edge-legend-row" title="${escHtml(title)}">
          <svg class="fm-edge-legend-line" width="28" height="10" viewBox="0 0 28 10" aria-hidden="true">
            ${edgeLegendMarker(edge)}
            <line x1="0" y1="5" x2="22" y2="5" stroke="var(${edge.colorVar})" stroke-width="${edge.width}"${dashAttr}${opacityAttr}></line>
            ${edgeLegendArrow(edge)}
          </svg>
          <span>${escHtml(edge.label)}</span>
        </div>
      `
    }).join('')}
  `
  overlays.appendChild(legend)

  canvas.appendChild(overlays)
}

function escHtml(value) {
  const div = document.createElement('div')
  div.textContent = value == null ? '' : String(value)
  return div.innerHTML
}

function edgeLegendArrow(edge) {
  const stroke = `var(${edge.colorVar})`

  if (edge.marker === 'circle') return ''

  if (edge.marker === 'diamond-filled') {
    return `<polygon points="22,5 25,2 28,5 25,8" fill="${stroke}" stroke="${stroke}" stroke-width="1"></polygon>`
  }

  if (edge.marker === 'diamond-open') {
    return `<polygon points="22,5 25,2 28,5 25,8" fill="none" stroke="${stroke}" stroke-width="1"></polygon>`
  }

  if (edge.marker === 'vee') {
    return `<polyline points="22,2 28,5 22,8" fill="none" stroke="${stroke}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"></polyline>`
  }

  return `<polygon points="22,2 28,5 22,8" fill="${stroke}"></polygon>`
}

function edgeLegendMarker(edge) {
  if (edge.marker !== 'circle') return ''
  return `<circle cx="24" cy="5" r="3" fill="var(${edge.colorVar})"></circle>`
}
