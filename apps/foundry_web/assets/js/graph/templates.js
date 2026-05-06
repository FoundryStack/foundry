import { covColor, getActionTypeColor, getTypeColor } from './colors'
import {
  STATUS_META,
  canShowGovernanceIndicators,
  formatNodeDisplayLabel,
  getClusterIcon,
  getTypeDisplayLabel,
  getTypeIcon,
  renderHeroIcon,
  shouldShowComplianceGap,
  shouldShowCoverageIndicator,
} from './semantics'

function nodeLabel(value, fallbackId) {
  return value || formatNodeDisplayLabel(fallbackId)
}

function escHtml(value) {
  const s = value == null ? '' : String(value)
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

export const STATUS_ICON_SVG = {
  covered: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13.5 4.5 6.5 11.5 2.5 7.5"></path></svg>',
  compliance_gap: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="8" cy="8" r="5.8"></circle><path d="M4 12 12 4"></path></svg>',
  sensitive: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M8 2 14 13H2L8 2Z"></path><path d="M8 6v3"></path><path d="M8 11.5h.01"></path></svg>',
  paper_trail: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M4 3h8"></path><path d="M4 6.5h8"></path><path d="M4 10h6"></path><path d="M4 13h4"></path></svg>',
  archival: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M3 5h10v8H3z"></path><path d="M2 3h12v2H2z"></path><path d="M6 8h4"></path></svg>',
  pm: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12.5 5A5 5 0 0 0 4 4"></path><path d="M12.5 2.5V5h-2.5"></path><path d="M3.5 11A5 5 0 0 0 12 12"></path><path d="M3.5 13.5V11H6"></path></svg>',
  oban: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="2.4"></circle><path d="M8 2.5v2"></path><path d="M8 11.5v2"></path><path d="M2.5 8h2"></path><path d="M11.5 8h2"></path><path d="M4.1 4.1l1.4 1.4"></path><path d="M10.5 10.5l1.4 1.4"></path><path d="M11.9 4.1l-1.4 1.4"></path><path d="M5.5 10.5l-1.4 1.4"></path></svg>',
  schedule: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="8" cy="8" r="5.5"></circle><path d="M8 4.5V8l2.5 1.5"></path></svg>',
  rl: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 4 2.5 8l4 4"></path><path d="M3 8h10.5"></path></svg>',
  fsm: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M8 2.5 13.5 8 8 13.5 2.5 8 8 2.5Z"></path><circle cx="8" cy="8" r="1.2" fill="currentColor" stroke="none"></circle></svg>',
  runbook: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M3.5 3h6.5a2 2 0 0 1 2 2v8H5.5a2 2 0 0 0-2 2V3Z"></path><path d="M5.5 6h4"></path><path d="M5.5 9h3"></path></svg>',
}

function statusIcon(key, title) {
  const icon = STATUS_ICON_SVG[key]
  if (!icon) return ''
  return `<span data-indicator="${key}" title="${escHtml(title)}">${icon}</span>`
}

export function buildIndicators(n) {
  const indicators = []

  if (shouldShowComplianceGap(n)) {
    indicators.push(statusIcon('compliance_gap', STATUS_META.compliance_gap.title))
  } else if (shouldShowCoverageIndicator(n)) {
    indicators.push(statusIcon('covered', STATUS_META.covered.title))
  }

  if (canShowGovernanceIndicators(n)) {
    if (n.sensitive) {
      indicators.push(statusIcon('sensitive', STATUS_META.sensitive.title))
    }

    if (n.pt || n.arch) {
      if (n.pt) indicators.push(statusIcon('paper_trail', STATUS_META.paper_trail.title))
      if (n.arch) indicators.push(statusIcon('archival', STATUS_META.archival.title))
    }

    if (n.pending_migrations) {
      indicators.push(statusIcon('pm', STATUS_META.pm.title))
    }

    if ((n.oban_queues || []).length > 0) {
      indicators.push(statusIcon('oban', STATUS_META.oban.title))
    }

    if (n.schedule) {
      indicators.push(statusIcon('schedule', `Schedule: ${n.schedule}`))
    }

    if (n.rl) {
      indicators.push(statusIcon('rl', STATUS_META.rl.title))
    }

    if (n.sm?.states) {
      indicators.push(statusIcon('fsm', STATUS_META.fsm.title))
    }

    if (n.runbook) {
      indicators.push(statusIcon('runbook', STATUS_META.runbook.title))
    }
  }

  if (indicators.length === 0) return ''
  return `<div class="status-icons">${indicators.join('')}</div>`
}

function compactChildTpl(data, opts = {}) {
  const type = opts.type || data.type || data.nodeKind
  const label = data.name || data.label || data.action_name || data.id
  const color = opts.typeColor || data.typeColor || getTypeColor(type)
  const icon = opts.icon || getTypeIcon(type)

  return `
    <div class="cy-node-html cy-node-sm">
      <div class="title-row">
        <span class="type-icon" style="color:${escHtml(color)}">${renderHeroIcon(icon)}</span>
        <span class="title" style="color:${escHtml(color)}">${escHtml(label)}</span>
      </div>
    </div>
  `
}

export function entityTpl(data) {
  const n = data

  if (n.type === 'external') {
    const color = escHtml(n.typeColor || getTypeColor('external'))
    return `
      <div class="cy-node-html cy-external-node">
        <div class="title-row">
          <span class="type-icon" style="color:${color}">${renderHeroIcon(getTypeIcon('external'))}</span>
          <span class="title" style="color:${color}">${nodeLabel(n.display_label, n.id)}</span>
        </div>
      </div>
    `
  }

  const jobAnnotation = n.type === 'job' && (n.oban_queues?.length > 0 || n.schedule)
    ? `<div class="node-subline">${STATUS_ICON_SVG.oban} ${escHtml(n.oban_queues?.[0] || 'default')}${n.schedule ? ' · ' + escHtml(n.schedule) : ''}</div>`
    : ''

  const triggerAnnotation = n.type === 'trigger' && (n.routes?.length > 0)
    ? `<div style="font-size:8px;color:var(--fg-ac);margin-top:2px;font-family:var(--font-mono)">${n.routes[0].r}</div>`
    : ''

  return `
    <div class="cy-node-html">
      ${buildIndicators(n)}
      <div class="domain-row">
        <span style="color: var(--fg-t2)">${n.domain || 'N/A'}</span>
      </div>
      <div class="title-row">
        <span class="type-icon" style="color:${escHtml(n.typeColor || getTypeColor(n.type))}">
          ${renderHeroIcon(getTypeIcon(n.type))}
        </span>
        <span class="title">${escHtml(nodeLabel(n.display_label, n.id))}</span>
      </div>
      ${jobAnnotation}
      ${triggerAnnotation}
      ${n.cov > 0 ? `
        <div class="req-badges">
          <div style="width:${n.cov}%; height:3px; background:${covColor(n.cov)}; border-radius:1px"></div>
        </div>
      ` : ''}
    </div>
  `
}

export function clusterTpl(data) {
  const n = data

  const color = n.typeColor || getTypeColor(n.type || 'cluster')
  const name = n.name || n.label || n.display_label || formatNodeDisplayLabel(n.id)
  const cov = n.cov ?? 0
  const isDomainCluster = getTypeDisplayLabel(n) === 'domain'
  const titleRowClass = isDomainCluster
    ? 'title-row boundary-title-row boundary-title-row-domain'
    : 'title-row boundary-title-row boundary-title-row-subcluster'

  const icon = getClusterIcon(n)

  return `
    <div class="cy-node-html cy-node-boundary">
      ${buildIndicators(n)}
      <div class="${titleRowClass}">
        <span class="type-icon" style="color:${escHtml(color)}">${renderHeroIcon(icon, 'size-4')}</span>
        <span class="title" style="color:${escHtml(color)}">${escHtml(name)}</span>
      </div>
      ${cov > 0 ? `<div class="req-badges"><div style="width:${cov}%; height:3px; background:${covColor(cov)}; border-radius:1px"></div></div>` : ''}
    </div>
  `
}

export function boundaryTpl(data) {
  return clusterTpl(data)
}

export function stepTpl(data) {
  const isAgent = data.type === 'agent' || data.step_kind === 'agent'
  return compactChildTpl(data, {
    type: isAgent ? 'agent' : 'step',
    typeColor: isAgent ? getTypeColor('agent') : getTypeColor('step'),
    icon: isAgent ? getTypeIcon('agent') : getTypeIcon('step'),
  })
}

export function actionTpl(data) {
  return compactChildTpl(data, {
    type: 'action',
    typeColor: getActionTypeColor(data.action_type),
    icon: getTypeIcon('action'),
  })
}

export function stateTpl(data) {
  return compactChildTpl(data, {
    type: 'state',
    typeColor: getTypeColor('state'),
    icon: getTypeIcon('state'),
  })
}
