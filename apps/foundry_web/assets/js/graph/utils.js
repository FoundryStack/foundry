import { domainCoverage, covColor, getDomainColor } from './colors'
import { EDGE_CATALOG, edgeLegendDash } from './edge_catalog'
import {
  getBoundaryKindLegend,
  getNodeKindLegend,
  getStatusLegend,
  LEGEND_SECTION_LABELS,
} from './semantics'
import { STATUS_ICON_SVG } from './templates'

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
  const canvas = container
  if (!canvas) return

  canvas.querySelector('#foundry-canvas-overlays')?.remove()

  const overlays = document.createElement('div')
  overlays.id = 'foundry-canvas-overlays'

  const coverage = domainCoverage(nodes)
  const nodeKindLegend = getNodeKindLegend()
  const boundaryKindLegend = getBoundaryKindLegend()
  const statusLegend = getStatusLegend()
  const coverageHtml = coverage
    .map(({ domain, avg }) =>
      `<div class="flex min-w-0 items-center gap-1.5">
        <span class="whitespace-nowrap font-mono text-[9px] font-semibold leading-none" style="color:${getDomainColor(domain)}">${escHtml(domain).toUpperCase()}</span>
        <div class="h-1 w-10 overflow-hidden rounded-[2px] bg-[color:color-mix(in_oklch,var(--fg-s3)_70%,transparent)]">
          <div class="h-full rounded-[inherit]" style="width:${avg}%;background:${covColor(avg)}"></div>
        </div>
        <span class="whitespace-nowrap font-mono text-[9px] font-semibold leading-none" style="color:${covColor(avg)}">${avg}%</span>
      </div>`)
    .join('')

  const header = document.createElement('div')
  header.className = 'pointer-events-auto absolute left-1/2 top-3 flex max-w-[calc(100%-2rem)] -translate-x-1/2 items-center gap-4 overflow-hidden rounded-md border border-[color:color-mix(in_oklch,var(--fg-b3)_55%,transparent)] bg-[color:color-mix(in_oklch,var(--fg-s2)_90%,transparent)] px-3.5 py-1.5 shadow-[0_8px_24px_rgba(0,0,0,0.22)] backdrop-blur-md'
  header.innerHTML = coverageHtml
  overlays.appendChild(header)

  const legend = document.createElement('div')
  legend.className = 'pointer-events-auto absolute bottom-3 left-3 flex max-w-[min(640px,calc(100%-24px))] flex-col gap-2.5 rounded-md border border-[color:color-mix(in_oklch,var(--fg-b3)_55%,transparent)] bg-[color:color-mix(in_oklch,var(--fg-s2)_90%,transparent)] px-3 py-2.5 text-[10px] shadow-[0_8px_24px_rgba(0,0,0,0.22)] backdrop-blur-md'
  legend.innerHTML = `
    <div class="flex flex-col gap-1.5">
      <div class="text-[8px] font-semibold uppercase leading-tight tracking-[0.1em] text-[color:color-mix(in_oklch,var(--fg-t2)_70%,transparent)]">${LEGEND_SECTION_LABELS.nodeKinds}</div>
      <div class="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-x-3 gap-y-1">
        ${nodeKindLegend.map(item => legendNodeItem(item)).join('')}
      </div>
    </div>
    <div class="flex flex-col gap-1.5">
      <div class="text-[8px] font-semibold uppercase leading-tight tracking-[0.1em] text-[color:color-mix(in_oklch,var(--fg-t2)_70%,transparent)]">${LEGEND_SECTION_LABELS.boundaryKinds}</div>
      <div class="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-x-3 gap-y-1">
        ${boundaryKindLegend.map(item => legendBoundaryItem(item)).join('')}
      </div>
    </div>
    <div class="flex flex-col gap-1.5">
      <div class="text-[8px] font-semibold uppercase leading-tight tracking-[0.1em] text-[color:color-mix(in_oklch,var(--fg-t2)_70%,transparent)]">${LEGEND_SECTION_LABELS.statusIcons}</div>
      <div class="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-x-3 gap-y-1">
        ${statusLegend.map(item => legendStatusItem(item)).join('')}
      </div>
    </div>
    <div class="flex flex-col gap-1.5">
      <div class="text-[8px] font-semibold uppercase leading-tight tracking-[0.1em] text-[color:color-mix(in_oklch,var(--fg-t2)_70%,transparent)]">${LEGEND_SECTION_LABELS.edgeTypes}</div>
      <div class="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-x-3 gap-y-1">
        ${EDGE_CATALOG.map(edge => legendEdgeItem(edge)).join('')}
      </div>
    </div>
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

function legendNodeItem(item) {
  return `
    <div class="flex items-center gap-1.5 whitespace-nowrap leading-tight text-[color:color-mix(in_oklch,var(--fg-tx)_70%,transparent)]" title="${escHtml(item.label)}">
      <span class="inline-flex shrink-0 items-center justify-center text-[11px]" style="color:${escHtml(item.color)}">${escHtml(item.icon)}</span>
      <span class="overflow-hidden text-ellipsis">${escHtml(item.label)}</span>
    </div>
  `
}

function legendBoundaryItem(item) {
  return `
    <div class="flex items-center gap-1.5 whitespace-nowrap leading-tight text-[color:color-mix(in_oklch,var(--fg-tx)_70%,transparent)]" title="${escHtml(item.detail || item.label)}">
      <span class="h-3 w-3 shrink-0 rounded-[3px] border border-[color:color-mix(in_oklch,var(--fg-b3)_70%,transparent)]" style="background:${item.color}"></span>
      <span class="overflow-hidden text-ellipsis">${escHtml(item.label)}</span>
    </div>
  `
}

function legendStatusItem(item) {
  const icon = STATUS_ICON_SVG[item.key]
  if (!icon) return ''

  return `
    <div class="flex items-center gap-1.5 whitespace-nowrap leading-tight text-[color:color-mix(in_oklch,var(--fg-tx)_70%,transparent)]" title="${escHtml(item.title)}">
      <span class="inline-flex shrink-0 items-center justify-center text-[11px] [&_svg]:h-[9px] [&_svg]:w-[9px] [&_svg]:stroke-current">${icon}</span>
      <span class="overflow-hidden text-ellipsis">${escHtml(item.label)}</span>
    </div>
  `
}

function legendEdgeItem(edge) {
  const dash = edgeLegendDash(edge)
  const dashAttr = dash ? ` stroke-dasharray="${dash}"` : ''
  const opacityAttr = edge.opacity ? ` opacity="${edge.opacity}"` : ''
  const title = `${edge.label}: ${edge.description} Source: ${edge.source}`
  return `
    <div class="flex items-center gap-1.5 whitespace-nowrap leading-tight text-[color:color-mix(in_oklch,var(--fg-tx)_70%,transparent)]" title="${escHtml(title)}">
      <svg class="shrink-0 overflow-visible" width="28" height="10" viewBox="0 0 28 10" aria-hidden="true">
        ${edgeLegendMarker(edge)}
        <line x1="0" y1="5" x2="22" y2="5" stroke="var(${edge.colorVar})" stroke-width="${edge.width}"${dashAttr}${opacityAttr}></line>
        ${edgeLegendArrow(edge)}
      </svg>
      <span class="overflow-hidden text-ellipsis">${escHtml(edge.label)}</span>
    </div>
  `
}
