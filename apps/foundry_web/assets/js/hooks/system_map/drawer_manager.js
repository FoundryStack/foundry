import { covColor, domainCoverage } from '../../foundry_graph'
import { UI_CONFIG } from '../../graph/config'
import { ResizablePanel } from './resizable_panel'

const SELECTORS = {
  drawer: 'fm-drawer',
  drawerClose: 'fm-drawer-close',
  panelDetails: 'fm-panel-details',
  panelFlow: 'fm-panel-flow',
  panelActions: 'fm-panel-actions',
  panelAuth: 'fm-panel-auth'
}

const STEP_KIND_COLORS = {
  read: 'var(--fg-bl)',
  write: 'var(--fg-gn)',
  map: 'var(--fg-pu)',
  custom: 'var(--fg-t2)'
}

const ACTION_SHORTCUTS = {
  resource: ['Edit schema', 'View migrations', 'Test coverage'],
  transfer: ['View pipeline', 'Trace execution', 'Replay'],
  reactor: ['Run simulation', 'Debug', 'Test coverage'],
  rule: ['View conditions', 'Test rule', 'Audit log'],
  liveview: ['Open in browser', 'View live metrics', 'Test coverage']
}

export class DrawerManager {
  constructor(normalizedNodes) {
    this.normalizedNodes = normalizedNodes
    this._panel = new ResizablePanel({
      elementId: SELECTORS.drawer,
      handleId: 'drawer-resize-handle',
      storageKey: UI_CONFIG.storageKeys.drawerWidth,
      defaultWidth: UI_CONFIG.drawerWidth.default,
      minWidth: UI_CONFIG.drawerWidth.min,
      maxWidth: UI_CONFIG.drawerWidth.max,
      isOpen: (drawer) => drawer.dataset.open === 'true',
    })
    this._initDrawer()
    this._panel.sync({ force: true })
  }

  _initDrawer() {
    const drawer = document.getElementById(SELECTORS.drawer)
    const closeBtn = document.getElementById(SELECTORS.drawerClose)

    if (!drawer) return

    if (this._boundDrawer !== drawer) {
      if (this._boundDrawer && this._drawerClickHandler) {
        this._boundDrawer.removeEventListener('click', this._drawerClickHandler)
      }

      this._drawerClickHandler = (event) => {
        const tab = event.target.closest('[data-tab]')
        if (!tab || !drawer.contains(tab)) return
        this.switchTab(tab.dataset.tab)
      }

      drawer.addEventListener('click', this._drawerClickHandler)
      this._boundDrawer = drawer
    }

    if (closeBtn && this._boundCloseBtn !== closeBtn) {
      if (this._boundCloseBtn && this._closeHandler) {
        this._boundCloseBtn.removeEventListener('click', this._closeHandler)
      }

      this._closeHandler = () => this.close()
      closeBtn.addEventListener('click', this._closeHandler)
      this._boundCloseBtn = closeBtn
    }
  }

  open() {
    const drawer = document.getElementById(SELECTORS.drawer)
    if (drawer) {
      drawer.dataset.open = 'true'
      this._panel.sync({ force: true })
    }
  }

  close() {
    const drawer = document.getElementById(SELECTORS.drawer)
    if (drawer) {
      drawer.dataset.open = 'false'
      this._panel.sync({ force: true })
    }
  }

  sync() {
    this._initDrawer()
    this._panel.sync()
  }

  switchTab(tabName) {
    const drawer = document.getElementById(SELECTORS.drawer)
    if (!drawer) return

    const tabs = drawer.querySelectorAll('[data-tab]')
    const activeTab = drawer.querySelector(`[data-tab="${tabName}"]`)
    const panels = {
      details: document.getElementById(SELECTORS.panelDetails),
      flow: document.getElementById(SELECTORS.panelFlow),
      actions: document.getElementById(SELECTORS.panelActions),
      auth: document.getElementById(SELECTORS.panelAuth)
    }

    if (!activeTab) return

    tabs.forEach(t => {
      t.dataset.active = 'false'
      t.classList.remove('active')
      t.classList.remove('tab-active')
    })
    activeTab.dataset.active = 'true'

    Object.values(panels).forEach(p => {
      if (p) p.classList.add('hidden')
    })

    if (panels[tabName]) {
      panels[tabName].classList.remove('hidden')
    }
  }

  renderForNode(nodeId, nodeData = null) {
    const stepMatch = nodeId.match(/^(.+):step:(\d+)$/)
    if (stepMatch) {
      const [, parentId, stepIdx] = stepMatch
      const parentNode = this.normalizedNodes.get(parentId)
      if (!parentNode) return
      const step = parentNode.steps?.[parseInt(stepIdx)]
      if (!step) return
      this._renderStepDetailsPanel(step, parentNode)
      this.switchTab('details')
      return
    }

    const actionMatch = nodeId.match(/^(.+):action:(.+)$/)
    if (actionMatch) {
      const [, parentId, rawActionName] = actionMatch
      const parentNode = this.normalizedNodes.get(parentId)
      if (!parentNode) return

      const actionName = this._normalizeActionName(rawActionName)
      const action =
        (parentNode.actions || []).find(a => this._normalizeActionName(a.name) === actionName) || {
          name: actionName,
          type: nodeData?.action_type || 'unknown',
          description: nodeData?.description,
        }

      this._renderActionDetailsPanel(action, parentNode)
      this.switchTab('details')
      return
    }

    const stateMatch = nodeId.match(/^(.+):state:(.+)$/)
    if (stateMatch) {
      const [, parentId, rawStateName] = stateMatch
      const parentNode = this.normalizedNodes.get(parentId)
      if (!parentNode) return

      const stateName = rawStateName
      this._renderStateDetailsPanel(stateName, parentNode)
      this.switchTab('details')
      return
    }

    const node = this.normalizedNodes.get(nodeId)
    if (!node) return

    this._renderDetailsPanel(node)
    this._renderFlowPanel(node)
    this._renderActionsPanel(node)
    this._renderAuthPanel(node)
    this.switchTab('details')
  }

  renderFileContent({ path, content, line = null }) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const lines = String(content || '').split('\n')

    panel.innerHTML = `
      <div class="space-y-3">
        <div>
          <p class="text-xs text-base-content/50">File preview</p>
          <h3 class="font-mono font-semibold text-sm break-all">${this._esc(path || 'unknown')}</h3>
          ${line ? `<p class="mt-1 text-xs text-base-content/60">Focused line ${line}</p>` : ''}
        </div>
        <div class="overflow-hidden rounded-box border border-base-300/80 bg-base-100/90">
          <div class="max-h-[32rem] overflow-auto">
            <table class="w-full border-collapse font-mono text-[11px] leading-5">
              <tbody>
                ${lines.map((fileLine, index) => {
                  const lineNumber = index + 1
                  const isActive = lineNumber === line

                  return `
                    <tr class="${isActive ? 'bg-primary/10' : ''}" data-line="${lineNumber}">
                      <td class="select-none border-r border-base-300/80 px-3 py-0.5 text-right align-top text-base-content/40">${lineNumber}</td>
                      <td class="px-3 py-0.5 align-top text-base-content whitespace-pre-wrap break-words">${this._esc(fileLine)}</td>
                    </tr>
                  `
                }).join('')}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `

    this.switchTab('details')

    if (line) {
      const activeLine = panel.querySelector(`[data-line="${line}"]`)
      activeLine?.scrollIntoView({ block: 'center' })
    }
  }

  renderFileError({ path, reason }) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    panel.innerHTML = `
      <div class="rounded-box border border-error/30 bg-error/10 px-4 py-4">
        <p class="text-xs font-semibold uppercase tracking-[0.12em] text-error">File preview unavailable</p>
        <p class="mt-2 font-mono text-xs text-base-content break-all">${this._esc(path || 'unknown')}</p>
        <p class="mt-3 text-sm text-error">${this._esc(reason || 'unknown error')}</p>
      </div>
    `

    this.switchTab('details')
  }

  _renderActionDetailsPanel(action, parentNode) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const actionType = this._normalizeActionName(action.type || 'unknown')
    const transitions = (parentNode.sm?.transitions || []).filter(t => this._normalizeActionName(t.action) === this._normalizeActionName(action.name))

    let html = `
      <div class="space-y-3">
        <div>
          <p class="text-xs text-base-content/50">Action on</p>
          <h4 class="font-mono text-xs text-base-content/70">${this._esc(parentNode.id)}</h4>
        </div>
        <div>
          <h3 class="font-mono font-semibold text-sm">${this._esc(action.name || 'unnamed action')}</h3>
          <span class="text-xs text-base-content/60">${this._esc(actionType)}</span>
        </div>
    `

    if (action.description) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Description</div>
          <p class="text-xs">${this._esc(action.description)}</p>
        </div>
      `
    }

    if (transitions.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">State transitions (${transitions.length})</div>
          <div class="space-y-1">
            ${transitions.map(t => `<span class="text-xs font-mono">${this._esc(t.from)} → ${this._esc(t.to)}</span>`).join('')}
          </div>
        </div>
      `
    }

    html += `</div>`
    panel.innerHTML = html
  }

  _renderStateDetailsPanel(stateName, parentNode) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const outgoing = (parentNode.sm?.transitions || []).filter(t => t.from === stateName)
    const incoming = (parentNode.sm?.transitions || []).filter(t => t.to === stateName)

    let html = `
      <div class="space-y-3">
        <div>
          <p class="text-xs text-base-content/50">State in</p>
          <h4 class="font-mono text-xs text-base-content/70">${this._esc(parentNode.id)}</h4>
        </div>
        <div>
          <h3 class="font-mono font-semibold text-sm">${this._esc(stateName)}</h3>
        </div>
    `

    if (outgoing.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Outgoing transitions (${outgoing.length})</div>
          <div class="space-y-1">
            ${outgoing.map(t => `<span class="text-xs font-mono">${this._esc(t.action || 'transition')} → ${this._esc(t.to)}</span>`).join('')}
          </div>
        </div>
      `
    }

    if (incoming.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Incoming transitions (${incoming.length})</div>
          <div class="space-y-1">
            ${incoming.map(t => `<span class="text-xs font-mono">${this._esc(t.from)} → ${this._esc(t.action || 'transition')}</span>`).join('')}
          </div>
        </div>
      `
    }

    html += `</div>`
    panel.innerHTML = html
  }

  _renderStepDetailsPanel(step, parentNode) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const kindColor = STEP_KIND_COLORS[step.step_kind] || 'var(--fg-t2)'

    let html = `
      <div class="space-y-3">
        <div>
          <p class="text-xs text-base-content/50">Step in</p>
          <h4 class="font-mono text-xs text-base-content/70">${this._esc(parentNode.id)}</h4>
        </div>
        <div>
          <h3 class="font-mono font-semibold text-sm">${this._esc(step.name || 'unnamed')}</h3>
          <span style="color:${kindColor}" class="text-xs">${this._esc(step.step_kind || step.type || 'custom')}</span>
        </div>
    `

    if (step.description) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Description</div>
          <p class="text-xs">${this._esc(step.description)}</p>
        </div>
      `
    }

    if (step.target_resource) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Resource</div>
          <p class="text-xs font-mono">${this._esc(step.target_resource)}</p>
        </div>
      `
    }

    if (step.target_action) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Action</div>
          <p class="text-xs font-mono">${this._esc(step.target_action)}</p>
        </div>
      `
    }

    if (step.wait_for?.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Wait for</div>
          <div class="flex flex-wrap gap-1">
            ${step.wait_for.map(w => `<span class="text-xs font-mono bg-base-200 px-1 rounded">${this._esc(w)}</span>`).join('')}
          </div>
        </div>
      `
    }

    if (step.source_snippet) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Source</div>
          <pre class="text-xs overflow-x-auto bg-base-200 p-2 rounded whitespace-pre-wrap break-words">${this._esc(step.source_snippet)}</pre>
        </div>
      `
    }

    if (step.side_effects && step.side_effects.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Side Effects (${step.side_effects.length})</div>
          <div class="space-y-1">
            ${step.side_effects.map(se => {
              const badge = se.declared
                ? `<span class="badge badge-xs badge-success">${this._esc(se.type)}</span>`
                : `<span class="badge badge-xs badge-error">inferred ${this._esc(se.type)}</span>`
              const detail = se.name ? `: ${this._esc(se.name)}` : ''
              const idempotent = se.idempotent != null ? ` · ${se.idempotent ? 'idempotent' : 'non-idempotent'}` : ''
              return `<div class="flex items-center gap-1">${badge}<span class="text-xs text-base-content/70">${detail}${idempotent}</span></div>`
            }).join('')}
          </div>
        </div>
      `
    }

    html += `</div>`
    panel.innerHTML = html
  }

  _renderDetailsPanel(n) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const coverage = domainCoverage([n])
    const cov = coverage.length > 0 ? coverage[0].avg : n.cov

    let html = `
      <div class="space-y-3">
        <div>
          <h3 class="font-mono font-semibold text-sm">${this._esc(n.id)}</h3>
          <p class="text-xs text-base-content/60">${this._esc(n.type || 'unknown')}</p>
        </div>

        <div>
          <div class="text-xs text-base-content/50 mb-1">Coverage</div>
          <div class="flex items-center gap-2">
            <div class="flex-1 bg-base-300 rounded h-2 overflow-hidden">
              <div style="width: ${cov}%; height: 100%; background: ${covColor(cov)}"></div>
            </div>
            <span class="text-xs font-semibold">${cov}%</span>
          </div>
        </div>

        <div>
          <div class="text-xs text-base-content/50 mb-1">Domain</div>
          <p class="text-sm">${this._esc(n.domain || 'N/A')}</p>
        </div>

        <div>
          <div class="text-xs text-base-content/50 mb-1">Description</div>
          <p class="text-xs">${this._esc(n.description || 'No description')}</p>
        </div>
    `

    if (n.reqs && n.reqs.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Compliance (${n.reqs.length})</div>
          <div class="space-y-1">
            ${n.reqs.map(r => `<span class="text-xs">${this._esc(r)}</span>`).join('')}
          </div>
        </div>
      `
    }

    if (n.sm && n.sm.states && n.sm.states.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">States (${n.sm.states.length})</div>
          <div class="space-y-1">
            ${n.sm.states.map(s => `<span class="text-xs font-mono">${this._esc(s.name)}</span>`).join('')}
          </div>
        </div>
      `
    }

    if (n.actions && n.actions.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Actions (${n.actions.length})</div>
          <div class="space-y-1">
            ${n.actions.map(a => `<span class="text-xs font-mono">${this._esc(a.name)} <span class="text-base-content/50">(${this._esc(a.type || 'unknown')})</span></span>`).join('')}
          </div>
        </div>
      `
    }

    if (n.steps && n.steps.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Steps (${n.steps.length})</div>
          <div class="space-y-1">
            ${n.steps.map(s => `<span class="text-xs font-mono">${this._esc(s.name || 'unnamed')}</span>`).join('')}
          </div>
        </div>
      `
    }

    if (n.routes && n.routes.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Routes (${n.routes.length})</div>
        </div>
      `
    }

    if (n.flags && n.flags.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Feature Flags (${n.flags.length})</div>
          <div class="space-y-1">
            ${n.flags.map(f => `<span class="text-xs font-mono">${this._esc(f)}</span>`).join('')}
          </div>
        </div>
      `
    }

    if (n.runbook) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Runbook</div>
          <p class="text-xs truncate">${this._esc(n.runbook)}</p>
        </div>
      `
    }

    html += `</div>`
    panel.innerHTML = html
  }

  renderForScenario(scenario) {
    if (!scenario) return
    this._renderScenarioFlowPanel(scenario)
    this.open()
    this.switchTab('flow')
  }

  _renderScenarioFlowPanel(scenario) {
    const panel = document.getElementById(SELECTORS.panelFlow)
    if (!panel) return

    const renderSteps = (title, steps) => {
      if (!steps || steps.length === 0) return ''
      return `
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.08em] text-base-content">${title}</p>
          <ul class="mt-1 space-y-1">
            ${steps.map(step => `<li class="flex gap-2 text-xs text-base-content/80"><span>•</span><span>${this._esc(step)}</span></li>`).join('')}
          </ul>
        </div>
      `
    }

    const nodes_html = scenario.nodes && scenario.nodes.length ? `
      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-base-content">Participating Nodes</p>
        <div class="mt-1 flex flex-wrap gap-1">
          ${scenario.nodes.map(n => `<span class="inline-block rounded bg-base-300 px-2 py-1 text-[10px] text-base-content/70">${this._esc(n)}</span>`).join('')}
        </div>
      </div>
    ` : ''

    const compliance_html = scenario.compliance_links && scenario.compliance_links.length ? `
      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.08em] text-base-content">Compliance</p>
        <div class="mt-1 flex flex-wrap gap-1">
          ${scenario.compliance_links.map(link => `<span class="inline-block rounded bg-warning/20 px-2 py-1 text-[10px] font-mono text-warning">${this._esc(link)}</span>`).join('')}
        </div>
      </div>
    ` : ''

    panel.innerHTML = `
      <div class="space-y-3">
        ${renderSteps('GIVEN', scenario.steps?.given || [])}
        ${renderSteps('WHEN', scenario.steps?.when || [])}
        ${renderSteps('THEN', scenario.steps?.then || [])}
        ${nodes_html}
        ${compliance_html}
      </div>
    `
  }

  _renderFlowPanel(n) {
    const panel = document.getElementById(SELECTORS.panelFlow)
    if (!panel) return

    // If node has scenario_origins, list them
    if (n.scenario_origins && n.scenario_origins.length > 0) {
      const html = `
        <div class="space-y-2">
          <p class="text-xs font-semibold uppercase tracking-[0.08em] text-base-content">Scenarios Involving This Node</p>
          <div class="space-y-1">
            ${n.scenario_origins.map(scen_id => `
              <button class="w-full rounded-box border border-base-300/50 bg-base-300/30 px-2 py-1.5 text-left text-xs text-base-content hover:bg-base-300/60 transition-colors"
                      phx-click="select_scenario" phx-value-id="${this._esc(scen_id)}">
                ${this._esc(scen_id)}
              </button>
            `).join('')}
          </div>
        </div>
      `
      panel.innerHTML = html
    } else {
      panel.innerHTML = `
        <div class="text-center py-6">
          <p class="text-xs text-base-content/50">No scenarios defined for this node yet</p>
        </div>
      `
    }
  }

  _renderActionsPanel(n) {
    const panel = document.getElementById(SELECTORS.panelActions)
    if (!panel) return

    const actions = ACTION_SHORTCUTS[n.type] || ['Open details', 'View in codebase']

    const html = `
      <div class="space-y-2">
        ${actions.map(a => `
          <button class="btn btn-sm btn-ghost w-full justify-start text-xs">
            ${this._esc(a)}
          </button>
        `).join('')}
      </div>
    `
    panel.innerHTML = html
  }

  _renderAuthPanel(node) {
    const panel = document.getElementById(SELECTORS.panelAuth)
    if (!panel) return

    if (node.type !== 'resource') {
      panel.innerHTML = '<p class="text-xs text-base-content/50">N/A for this node type</p>'
      return
    }

    panel.innerHTML = `
      <div class="text-xs text-base-content/50">
        <p>Authorization data not yet available</p>
      </div>
    `
  }

  _normalizeActionName(name) {
    if (name == null) return null
    return String(name).replace(/^:/, '')
  }

  _esc(s) {
    const div = document.createElement('div')
    div.textContent = s
    return div.innerHTML
  }

  destroy() {
    if (this._boundCloseBtn && this._closeHandler) {
      this._boundCloseBtn.removeEventListener('click', this._closeHandler)
    }

    if (this._boundDrawer && this._drawerClickHandler) {
      this._boundDrawer.removeEventListener('click', this._drawerClickHandler)
    }

    this._boundDrawer = null
    this._boundCloseBtn = null
    this._panel.destroy()
  }
}
