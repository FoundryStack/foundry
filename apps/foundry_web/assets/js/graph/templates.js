import { covColor } from './colors'

export function shortLabel(id) {
  if (!id) return id
  if (id.startsWith('external:')) return id.replace('external:', '')
  const parts = id.split('.')
  return parts[parts.length - 1]
}

export function buildIndicators(n) {
  const indicators = []

  if (n.cov >= 80) {
    indicators.push(`<span data-indicator="covered" title="Test coverage ≥80%">✓</span>`)
  } else if (n.gap) {
    indicators.push(`<span data-indicator="gap" title="Compliance gap">⊘</span>`)
  }

  if (n.sensitive) {
    indicators.push(`<span data-indicator="sensitive" title="Sensitive data">⚠</span>`)
  }

  if (n.pt || n.arch) {
    if (n.pt)   indicators.push(`<span data-indicator="paper_trail" title="Paper Trail">≣</span>`)
    if (n.arch) indicators.push(`<span data-indicator="archival" title="Archival">⊟</span>`)
  }

  if (n.pending_migrations) {
    indicators.push(`<span data-indicator="pm" title="Pending migrations">↻</span>`)
  }

  if ((n.oban_queues || []).length > 0) {
    indicators.push(`<span data-indicator="oban" title="Oban queues">⚙</span>`)
  }
  if (n.schedule) {
    indicators.push(`<span data-indicator="schedule" title="Schedule: ${n.schedule}">⏱</span>`)
  }

  if (n.rl) {
    indicators.push(`<span data-indicator="rl" title="Rate limited">⬅</span>`)
  }

  if (n.sm?.states) {
    indicators.push(`<span data-indicator="fsm" title="State machine">◊</span>`)
  }

  if (n.runbook) {
    indicators.push(`<span data-indicator="runbook" title="Runbook">📖</span>`)
  }

  return `<div class="status-icons">${indicators.join('')}</div>`
}

export function entityTpl(data) {
  const n = data

  if (n.type === 'external') {
    return `
      <div class="cy-node-html cy-external-node">
        <span class="title">${shortLabel(n.id)}</span>
      </div>
    `
  }

  const jobAnnotation = n.type === 'job' && (n.oban_queues?.length > 0 || n.schedule)
    ? `<div style="font-size:9px;color:var(--fg-pu);margin-top:1px">⚙ ${n.oban_queues?.[0] || 'default'}${n.schedule ? ' · ' + n.schedule : ''}</div>`
    : ''

  const triggerAnnotation = n.type === 'trigger' && (n.routes?.length > 0)
    ? `<div style="font-size:8px;color:var(--fg-ac);margin-top:2px;font-family:var(--font-mono)">${n.routes[0].r}</div>`
    : ''

  return `
    <div class="cy-node-html">
      ${buildIndicators(n)}
      <div class="domain-row">
        <span class="domain-dot" style="background: ${covColor(n.cov)}"></span>
        <span style="color: var(--fg-t2)">${n.domain || 'N/A'}</span>
      </div>
      <div class="title-row">
        <span class="type-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <circle cx="12" cy="12" r="10"></circle>
          </svg>
        </span>
        <span class="title">${shortLabel(n.id)}</span>
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

export function domainClusterTpl(data) {
  return `
    <div class="cy-node-html cy-domain-cluster">
      <span class="domain-cluster-label" style="color:${data.typeColor}">${data.label}</span>
    </div>
  `
}

export function clusterTpl(data) {
  const n = data
  if (data.nodeKind === 'domain-cluster' || data.classes?.includes('domain-cluster')) return domainClusterTpl(data)

  const icons = { transfer: '⇄', reactor: '◈', job: '⚙', blueprint: '◇' }
  const icon = icons[n.type] || (n.sm ? '◊' : '◈')
  const cov = n.cov ?? 0

  return `
    <div class="cy-node-html cy-node-boundary" style="margin-left: 12px; margin-top: 12px">
      ${buildIndicators(n)}
      <div class="domain-row">
        <span class="domain-dot" style="background: ${covColor(cov)}"></span>
        <span style="color: var(--fg-t2)">${n.domain || ''}</span>
      </div>
      <div class="title-row">
        <span class="type-icon">${icon}</span>
        <span class="title">${shortLabel(n.id)}</span>
      </div>
      ${cov > 0 ? `<div class="req-badges"><div style="width:${cov}%; height:3px; background:${covColor(cov)}; border-radius:1px"></div></div>` : ''}
    </div>
  `
}

export function boundaryTpl(data) {
  return clusterTpl(data)
}

export function stepTpl(data) {
  const icons = { read: '📖', write: '✏', map: '◈', custom: '⚙' }
  const icon = icons[data.step_kind] || '⚙'
  const ses = data.side_effects || []
  const seBadges = ses.map(se => {
    const color = se.declared ? 'var(--fg-gn)' : 'var(--fg-rd)'
    const prefix = se.declared ? '' : '⚠ '
    return `<span style="display:inline-block;font-size:7px;padding:1px 3px;border-radius:2px;background:${color};color:var(--fg-base);margin:1px">${prefix}${se.type}</span>`
  }).join('')
  return `
    <div class="cy-node-html cy-step-node" style="text-align:center;font-size:9px;line-height:1.2;padding:2px 4px">
      <span>${icon}</span><br>
      <span style="color:var(--fg-tx)">${data.label || data.id}</span>
      ${ses.length > 0 ? `<div style="margin-top:2px">${seBadges}</div>` : ''}
    </div>
  `
}

export function actionTpl(data) {
  const icons = {
    read: '📖',
    create: '✚',
    update: '✏',
    destroy: '🗑',
  }
  const icon = icons[data.action_type] || '⚙'
  return `
    <div class="cy-node-html cy-action-node" style="text-align:center;font-size:9px;line-height:1.2;padding:2px 4px">
      <span>${icon}</span><br>
      <span style="color:var(--fg-tx)">${data.label || data.action_name || data.id}</span>
    </div>
  `
}

export function stateTpl(data) {
  return `
    <div class="cy-node-html cy-state-node" style="text-align:center;font-size:9px;line-height:1.2;padding:2px 4px">
      <span class="state-dot"></span>
      <span style="color:var(--fg-tx)">${data.label || data.name || data.id}</span>
    </div>
  `
}
