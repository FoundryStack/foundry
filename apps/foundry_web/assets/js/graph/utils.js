import { domainCoverage, covColor } from './colors'

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
