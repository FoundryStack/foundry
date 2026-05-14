import { EDGE_CATALOG, edgeLegendDash } from './edge_catalog'
import {
  formatNodeDisplayLabel,
  getBoundaryKindLegend,
  getNodeKindLegend,
  getStatusLegend,
  LEGEND_SECTION_LABELS,
  renderHeroIcon,
} from './semantics'
import { STATUS_ICON_SVG } from './templates'

export function searchMatch(node, query) {
  const q = query.toLowerCase()
  return (
    (node.id          || '').toLowerCase().includes(q) ||
    (node.display_label || formatNodeDisplayLabel(node.id) || '').toLowerCase().includes(q) ||
    (node.type        || '').toLowerCase().includes(q) ||
    (node.domain      || '').toLowerCase().includes(q) ||
    (node.description || '').toLowerCase().includes(q) ||
    (node.reqs || []).join(' ').toLowerCase().includes(q)
  )
}

export function buildCanvasOverlays(container, nodes, graph) {
  const canvas = container
  if (!canvas) return

  canvas.querySelector('#foundry-canvas-overlays')?.remove()

  const overlays = document.createElement('div')
  overlays.id = 'foundry-canvas-overlays'

  const nodeKindLegend = getNodeKindLegend()
  const boundaryKindLegend = getBoundaryKindLegend()
  const statusLegend = getStatusLegend()
  const metaExpanded = graph?._legendMetaExpanded ?? false
  const edgesVisible = graph?._legendEdgesVisible ?? false

  const legend = document.createElement('div')
  legend.className = 'fm-graph-legend pointer-events-auto absolute bottom-3 left-[calc(var(--foundry-sidebar-width,240px)+24px)] flex max-w-[min(560px,calc(100%-24px))] flex-col text-[10px]'
  legend.dataset.metaExpanded = metaExpanded ? 'true' : 'false'
  legend.dataset.edgesVisible = edgesVisible ? 'true' : 'false'
  legend.innerHTML = `
    <div class="relative flex flex-col gap-2">
      <div class="pointer-events-none absolute bottom-full left-0 right-0 mb-2 flex flex-col gap-2">
        <div class="fm-legend-meta pointer-events-auto hidden rounded-2xl border border-white/10 bg-base-200/75 p-3 shadow-[0_12px_32px_rgba(0,0,0,0.24)] backdrop-blur-xl data-[expanded=true]:flex data-[expanded=true]:flex-col data-[expanded=true]:gap-2" data-expanded="${metaExpanded ? 'true' : 'false'}">
          <div class="flex flex-col gap-1.5">
            <div class="text-[8px] font-semibold uppercase leading-tight tracking-[0.1em] text-base-content/45">${LEGEND_SECTION_LABELS.nodeKinds}</div>
            <div class="grid grid-cols-[repeat(auto-fit,minmax(132px,1fr))] gap-x-3 gap-y-1">
              ${nodeKindLegend.map(item => legendNodeItem(item)).join('')}
            </div>
          </div>
          <div class="flex flex-col gap-1.5">
            <div class="text-[8px] font-semibold uppercase leading-tight tracking-[0.1em] text-base-content/45">${LEGEND_SECTION_LABELS.boundaryKinds}</div>
            <div class="grid grid-cols-[repeat(auto-fit,minmax(132px,1fr))] gap-x-3 gap-y-1">
              ${boundaryKindLegend.map(item => legendBoundaryItem(item)).join('')}
            </div>
          </div>
          <div class="flex flex-col gap-1.5">
            <div class="text-[8px] font-semibold uppercase leading-tight tracking-[0.1em] text-base-content/45">${LEGEND_SECTION_LABELS.statusIcons}</div>
            <div class="grid grid-cols-[repeat(auto-fit,minmax(132px,1fr))] gap-x-3 gap-y-1">
              ${statusLegend.map(item => legendStatusItem(item)).join('')}
            </div>
          </div>
        </div>
        <div class="fm-edge-legend pointer-events-auto hidden rounded-2xl border border-white/10 bg-base-200/75 p-3 shadow-[0_12px_32px_rgba(0,0,0,0.24)] backdrop-blur-xl data-[expanded=true]:flex data-[expanded=true]:flex-col data-[expanded=true]:gap-1.5" data-expanded="${edgesVisible ? 'true' : 'false'}">
          <div class="flex items-center justify-between gap-3">
            <div class="text-[8px] font-semibold uppercase leading-tight tracking-[0.1em] text-base-content/45">${LEGEND_SECTION_LABELS.edgeTypes}</div>
            <span class="text-[8px] uppercase tracking-[0.1em] text-base-content/40">Click to toggle</span>
          </div>
          <div class="fm-edge-legend-items grid grid-cols-[repeat(auto-fit,minmax(132px,1fr))] gap-x-3 gap-y-1">
            ${EDGE_CATALOG.map(edge => legendEdgeItem(edge)).join('')}
          </div>
        </div>
      </div>
      <div class="flex items-center justify-between gap-3 rounded-2xl border border-white/10 bg-base-200/75 px-3 py-2 shadow-[0_12px_32px_rgba(0,0,0,0.24)] backdrop-blur-xl">
        <button class="fm-legend-toggle flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-2.5 py-1.5 text-[10px] font-semibold uppercase tracking-[0.1em] text-base-content/75 transition hover:bg-white/10 hover:text-base-content data-[open=true]:border-white/15 data-[open=true]:bg-white/12 data-[open=true]:text-base-content" data-legend-toggle="meta" data-open="${metaExpanded ? 'true' : 'false'}" type="button">
          ${renderHeroIcon('hero-eye-solid')}
          <span>Node Kinds, Boundaries, Status Icons</span>
        </button>
        <button class="fm-legend-toggle flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-2.5 py-1.5 text-[10px] font-semibold uppercase tracking-[0.1em] text-base-content/75 transition hover:bg-white/10 hover:text-base-content data-[open=true]:border-white/15 data-[open=true]:bg-white/12 data-[open=true]:text-base-content" data-legend-toggle="edges" data-open="${edgesVisible ? 'true' : 'false'}" type="button">
          ${renderHeroIcon('hero-share-solid')}
          <span>${LEGEND_SECTION_LABELS.edgeTypes}</span>
        </button>
      </div>
    </div>
  `
  const metaPanel = legend.querySelector('.fm-legend-meta')
  const edgePanel = legend.querySelector('.fm-edge-legend')
  overlays.appendChild(legend)

  legend.querySelectorAll('[data-legend-toggle]').forEach(button => {
    button.addEventListener('click', () => {
      const section = button.getAttribute('data-legend-toggle')
      if (section === 'meta') {
        const expanded = legend.dataset.metaExpanded !== 'true'
        legend.dataset.metaExpanded = expanded ? 'true' : 'false'
        if (graph) graph._legendMetaExpanded = expanded
        button.dataset.open = expanded ? 'true' : 'false'
        if (metaPanel) metaPanel.dataset.expanded = expanded ? 'true' : 'false'
      }

      if (section === 'edges') {
        const visible = legend.dataset.edgesVisible !== 'true'
        legend.dataset.edgesVisible = visible ? 'true' : 'false'
        if (graph) graph._legendEdgesVisible = visible
        button.dataset.open = visible ? 'true' : 'false'
        if (edgePanel) edgePanel.dataset.expanded = visible ? 'true' : 'false'
      }
    })
  })

  legend.querySelectorAll('[data-edge-relation]').forEach(button => {
    const relation = button.getAttribute('data-edge-relation')
    const syncState = () => {
      const visible = graph?.isEdgeRelationVisible(relation) ?? true
      button.dataset.active = visible ? 'true' : 'false'
    }

    syncState()

    button.addEventListener('click', () => {
      graph?.toggleEdgeRelation(relation)
      syncState()
    })
  })

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
    <div class="flex items-center gap-1.5 whitespace-nowrap leading-tight text-base-content/70" title="${escHtml(item.label)}">
      <span class="inline-flex shrink-0 items-center justify-center text-[11px]" style="color:${escHtml(item.color)}">${renderHeroIcon(item.iconClass)}</span>
      <span class="overflow-hidden text-ellipsis">${escHtml(item.label)}</span>
    </div>
  `
}

function legendBoundaryItem(item) {
  return `
    <div class="flex items-center gap-1.5 whitespace-nowrap leading-tight text-base-content/70" title="${escHtml(item.detail || item.label)}">
      <span class="h-3 w-3 shrink-0 rounded-[3px] border border-white/10" style="background:${item.color}"></span>
      <span class="overflow-hidden text-ellipsis">${escHtml(item.label)}</span>
    </div>
  `
}

function legendStatusItem(item) {
  const icon = STATUS_ICON_SVG[item.key]
  if (!icon) return ''

  return `
    <div class="flex items-center gap-1.5 whitespace-nowrap leading-tight text-base-content/70" title="${escHtml(item.title)}">
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
    <button class="flex items-center gap-1.5 whitespace-nowrap rounded-lg border border-transparent px-1.5 py-1 leading-tight text-left text-base-content/70 transition hover:bg-white/5 data-[active=false]:opacity-35 data-[active=true]:border-white/10" title="${escHtml(title)}" data-edge-relation="${escHtml(edge.relation)}" data-active="true" type="button">
      <svg class="shrink-0 overflow-visible" width="28" height="10" viewBox="0 0 28 10" aria-hidden="true">
        ${edgeLegendMarker(edge)}
        <line x1="0" y1="5" x2="22" y2="5" stroke="var(${edge.colorVar})" stroke-width="${edge.width}"${dashAttr}${opacityAttr}></line>
        ${edgeLegendArrow(edge)}
      </svg>
      <span class="overflow-hidden text-ellipsis">${escHtml(edge.label)}</span>
    </button>
  `
}
