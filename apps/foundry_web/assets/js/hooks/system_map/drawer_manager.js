import { covColor } from '../../foundry_graph'
import { UI_CONFIG } from '../../graph/config'
import { formatNodeDisplayLabel, formatStepKindLabel } from '../../graph/semantics'
import { ResizablePanel } from './resizable_panel'

const SELECTORS = {
  drawer: 'fm-drawer',
  drawerClose: 'fm-drawer-close',
  drawerTitle: 'fm-drawer-title',
  drawerSubtitle: 'fm-drawer-subtitle',
  panelDetails: 'fm-panel-details',
}

const STEP_KIND_TONES = {
  read: 'info',
  write: 'success',
  map: 'accent',
  transform: 'accent',
  branch: 'warning',
  decision: 'warning',
  agent: 'agent',
  scorer: 'agent',
  custom: 'muted',
  step: 'step',
}

export class DrawerManager {
  constructor(normalizedNodes, pushEvent, options = {}) {
    this.normalizedNodes = normalizedNodes
    this._pushEvent = pushEvent || (() => {})
    this._onNodeSelect = options.onNodeSelect || (() => {})
    this._onStartPreview = options.onStartPreview || (() => {})
    this._activeNodeSelection = null
    this._activeScenario = null
    this._activeFileView = null
    this._panel = new ResizablePanel({
      elementId: SELECTORS.drawer,
      handleId: 'drawer-resize-handle',
      storageKey: UI_CONFIG.storageKeys.drawerWidth,
      cssVarName: '--foundry-drawer-width',
      defaultWidth: UI_CONFIG.drawerWidth.default,
      minWidth: UI_CONFIG.drawerWidth.min,
      maxWidth: UI_CONFIG.drawerWidth.max,
      isOpen: drawer => drawer.dataset.open === 'true',
    })
    this._initDrawer()
    this._panel.sync({ force: true })
  }

  _initDrawer() {
    const drawer = document.getElementById(SELECTORS.drawer)
    const closeBtn = document.getElementById(SELECTORS.drawerClose)
    const previewBtn = document.getElementById('fm-drawer-preview-btn')
    const detailsPanel = document.getElementById(SELECTORS.panelDetails)

    if (!drawer) return

    if (closeBtn && this._boundCloseBtn !== closeBtn) {
      if (this._boundCloseBtn && this._closeHandler) {
        this._boundCloseBtn.removeEventListener('click', this._closeHandler)
      }

      this._closeHandler = () => this.close()
      closeBtn.addEventListener('click', this._closeHandler)
      this._boundCloseBtn = closeBtn
    }

    if (previewBtn && this._boundPreviewBtn !== previewBtn) {
      if (this._boundPreviewBtn && this._previewBtnHandler) {
        this._boundPreviewBtn.removeEventListener('click', this._previewBtnHandler)
      }

      this._previewBtnHandler = () => {
        const route = previewBtn.dataset.startPreviewRoute || '/'
        this._onStartPreview(route)
      }
      previewBtn.addEventListener('click', this._previewBtnHandler)
      this._boundPreviewBtn = previewBtn
    }

    if (detailsPanel && this._boundDetailsPanel !== detailsPanel) {
      if (this._boundDetailsPanel && this._detailsClickHandler) {
        this._boundDetailsPanel.removeEventListener('click', this._detailsClickHandler)
      }

      this._detailsClickHandler = async event => {
        const copyBtn = event.target.closest('[data-copy-value]')
        if (copyBtn) {
          const value = copyBtn.getAttribute('data-copy-value') || ''
          try {
            await navigator.clipboard.writeText(value)
            copyBtn.dataset.copied = 'true'
            setTimeout(() => { copyBtn.dataset.copied = 'false' }, 1200)
          } catch (_error) {}
          return
        }

        const stepBtn = event.target.closest('[data-scenario-step-id]')
        if (stepBtn && this._activeScenario?.id === stepBtn.dataset.scenarioId) {
          this._activeScenario = {
            ...this._activeScenario,
            active_step_id: stepBtn.dataset.scenarioStepId,
            active_step:
              (this._activeScenario.flow || []).find(
                step => step.id === stepBtn.dataset.scenarioStepId,
              ) || this._activeScenario.active_step,
          }
          this._renderScenarioPanel(this._activeScenario)
          this._pushEvent('select_scenario_step', {
            scenario_id: stepBtn.dataset.scenarioId,
            step_id: stepBtn.dataset.scenarioStepId,
          })
          return
        }

        const relatedNodeBtn = event.target.closest('[data-related-node-id]')
        if (relatedNodeBtn) {
          const nodeId = relatedNodeBtn.dataset.relatedNodeId
          if (nodeId) {
            this._onNodeSelect(nodeId)
          }
          return
        }

        const coverageBtn = event.target.closest('[data-show-coverage-node-id]')
        if (coverageBtn) {
          const nodeId = coverageBtn.dataset.showCoverageNodeId
          if (nodeId) {
            this._pushEvent('show_node_coverage', { id: nodeId })
          }
          return
        }

        const startPreviewBtn = event.target.closest('[data-start-preview-route]')
        if (startPreviewBtn) {
          this._onStartPreview(startPreviewBtn.dataset.startPreviewRoute || '/')
          return
        }

        const stopPreviewBtn = event.target.closest('[data-stop-preview]')
        if (stopPreviewBtn) {
          this._pushEvent('stop_preview', {})
          return
        }
      }

      detailsPanel.addEventListener('click', this._detailsClickHandler)
      this._boundDetailsPanel = detailsPanel
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
    this._renderActivePanel()
  }

  switchTab(_tabName) {}

  renderForNode(nodeId, nodeData = null) {
    this._activeScenario = null
    this._activeFileView = null
    this._activeNodeSelection = { nodeId, nodeData }

    const stepMatch = nodeId.match(/^(.+):step:(\d+)$/)
    if (stepMatch) {
      const [, parentId, stepIdx] = stepMatch
      const parentNode = this.normalizedNodes.get(parentId)
      const step = parentNode?.steps?.[parseInt(stepIdx, 10)]
      if (!parentNode || !step) return
      this._setHeader(step.name || 'Step', this._displayNodeLabel(parentNode), { showPreview: false })
      this._renderStepDetailsPanel(step)
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

      this._setHeader(action.name || 'Action', this._displayNodeLabel(parentNode), { showPreview: false })
      this._renderActionDetailsPanel(action, parentNode)
      return
    }

    const stateMatch = nodeId.match(/^(.+):state:(.+)$/)
    if (stateMatch) {
      const [, parentId, rawStateName] = stateMatch
      const parentNode = this.normalizedNodes.get(parentId)
      if (!parentNode) return
      this._setHeader(rawStateName, this._displayNodeLabel(parentNode), { showPreview: false })
      this._renderStateDetailsPanel(rawStateName, parentNode)
      return
    }

    const node = this.normalizedNodes.get(nodeId) || nodeData
    if (!node) return

    const showPreview = node.type === 'page'
    const previewRoute = this._previewRouteForNode(node)
    this._setHeader(this._displayNodeLabel(node), node.type || 'node', { showPreview, previewRoute })
    this._renderDetailsPanel(node)
  }

  _previewRouteForNode(node) {
    const rawRoute = typeof node?.page_route === 'string' ? node.page_route.trim() : ''

    if (rawRoute === '') return '/'

    const normalizedRoute = rawRoute.startsWith('/') ? rawRoute : `/${rawRoute}`
    return normalizedRoute.replace(/:([^/]+)/g, 'preview')
  }

  renderForScenario(scenario) {
    if (!scenario) return
    this._activeNodeSelection = null
    this._activeFileView = null
    this._activeScenario = scenario
    this._setHeader(scenario.test_header || scenario.name || 'Scenario', scenario.test_subheader || '')
    this._renderScenarioPanel(scenario)
    this.open()
  }

  clearScenario() {
    this._activeScenario = null
    this._activeNodeSelection = null
    this._activeFileView = null
    const previewBtn = document.getElementById('fm-drawer-preview-btn')
    if (previewBtn) {
      previewBtn.classList.add('hidden')
      delete previewBtn.dataset.startPreviewRoute
    }
    this.close()
  }

  renderFileContent({ path, content, line = null }) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    this._activeNodeSelection = null
    this._activeScenario = null
    this._activeFileView = { kind: 'content', path, content, line }

    this._setHeader(path || 'File preview', line ? `Line ${line}` : 'Source')

    const lines = String(content || '').split('\n')

    panel.innerHTML = `
      <div class="space-y-3">
        <div class="overflow-hidden rounded-2xl border border-white/10 bg-base-100/90">
          <div class="max-h-[32rem] overflow-auto">
            <table class="w-full border-collapse font-mono text-[11px] leading-5">
              <tbody>
                ${lines.map((fileLine, index) => {
                  const lineNumber = index + 1
                  const isActive = lineNumber === line

                  return `
                    <tr class="${isActive ? 'bg-primary/10' : ''}" data-line="${lineNumber}">
                      <td class="select-none border-r border-white/10 px-3 py-0.5 text-right align-top text-base-content/40">${lineNumber}</td>
                      <td class="whitespace-pre-wrap break-words px-3 py-0.5 align-top text-base-content">${this._esc(fileLine)}</td>
                    </tr>
                  `
                }).join('')}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `

    if (line) {
      const activeLine = panel.querySelector(`[data-line="${line}"]`)
      activeLine?.scrollIntoView({ block: 'center' })
    }
  }

  renderFileError({ path, reason }) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    this._activeNodeSelection = null
    this._activeScenario = null
    this._activeFileView = { kind: 'error', path, reason }

    this._setHeader('File preview unavailable', path || 'unknown')
    panel.innerHTML = `
      <div class="rounded-2xl border border-error/30 bg-error/10 px-4 py-4">
        <p class="text-sm text-error">${this._esc(reason || 'unknown error')}</p>
      </div>
    `
  }

  renderProposalFilePreview({ path, content, diff, status, added_lines = 0, removed_lines = 0 }) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    this._activeNodeSelection = null
    this._activeScenario = null
    this._activeFileView = { kind: 'proposal', path, content, diff, status, added_lines, removed_lines }

    this._setHeader(path || 'Proposal preview', `${status || 'modified'} · ${added_lines}+ ${removed_lines}-`)

    const lines = String(content || '').split('\n')

    panel.innerHTML = `
      <div class="space-y-3">
        <details open class="overflow-hidden rounded-2xl border border-white/10 bg-[#0d1117]">
          <summary class="cursor-pointer px-3 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-base-content/70">
            Unified diff
          </summary>
          <div class="border-t border-white/10 px-3 py-3">
            <pre class="overflow-x-auto rounded-xl bg-[#0d1117] px-3 py-3 font-mono text-[11px] leading-5 text-[#c9d1d9]">${this._esc(diff || '')}</pre>
          </div>
        </details>
        <div class="overflow-hidden rounded-2xl border border-white/10 bg-base-100/90">
          <div class="max-h-[32rem] overflow-auto">
            <table class="w-full border-collapse font-mono text-[11px] leading-5">
              <tbody>
                ${lines.map((fileLine, index) => {
                  const lineNumber = index + 1
                  return `
                    <tr data-line="${lineNumber}">
                      <td class="select-none border-r border-white/10 px-3 py-0.5 text-right align-top text-base-content/40">${lineNumber}</td>
                      <td class="whitespace-pre-wrap break-words px-3 py-0.5 align-top text-base-content">${this._esc(fileLine)}</td>
                    </tr>
                  `
                }).join('')}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `
  }

  _renderActionDetailsPanel(action, parentNode) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const actionType = this._normalizeActionName(action.type || 'unknown')
    const transitions = (parentNode.sm?.transitions || []).filter(
      t => this._normalizeActionName(t.action) === this._normalizeActionName(action.name),
    )

    panel.innerHTML = `
      <div class="space-y-3">
        ${this._bodyCard(action.description ? `<p class="text-sm leading-6 text-base-content/85">${this._esc(action.description)}</p>` : '')}
        ${this._fieldCard('Kind', `<p class="text-sm text-base-content">${this._esc(actionType)}</p>`)}
        ${transitions.length > 0 ? this._fieldCard(
          'State transitions',
          `<div class="space-y-1">${transitions.map(t => `<p class="font-mono text-xs text-base-content/80">${this._esc(t.from)} → ${this._esc(t.to)}</p>`).join('')}</div>`,
        ) : ''}
      </div>
    `
  }

  _renderStateDetailsPanel(stateName, parentNode) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const outgoing = (parentNode.sm?.transitions || []).filter(t => t.from === stateName)
    const incoming = (parentNode.sm?.transitions || []).filter(t => t.to === stateName)
    const blocks = []

    if (outgoing.length > 0) {
      blocks.push(this._fieldCard(
        'Outgoing',
        `<div class="space-y-1">${outgoing.map(t => `<p class="font-mono text-xs text-base-content/80">${this._esc(t.action || 'transition')} → ${this._esc(t.to)}</p>`).join('')}</div>`,
      ))
    }

    if (incoming.length > 0) {
      blocks.push(this._fieldCard(
        'Incoming',
        `<div class="space-y-1">${incoming.map(t => `<p class="font-mono text-xs text-base-content/80">${this._esc(t.from)} → ${this._esc(t.action || 'transition')}</p>`).join('')}</div>`,
      ))
    }

    panel.innerHTML = blocks.length > 0
      ? `<div class="space-y-3">${blocks.join('')}</div>`
      : this._emptyState('No state transitions were extracted for this state.')
  }

  _renderStepDetailsPanel(step) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const kind = formatStepKindLabel(step.step_kind || step.type || 'step')
    const tone = this._stepKindTone(step.step_kind || step.type)
    const blocks = [
      this._bodyCard(`
        <div class="space-y-3">
          <p class="text-sm leading-6 text-base-content/85">${this._esc(step.description || 'No description')}</p>
          <div class="flex items-center justify-between gap-3">
            <span class="text-[10px] font-semibold uppercase tracking-[0.12em] text-base-content/35">Step</span>
            <span class="rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.12em]" data-step-tone="${tone}">${this._esc(kind)}</span>
          </div>
        </div>
      `),
    ]

    if (step.target_resource) {
      blocks.push(this._fieldCard('Resource', `<p class="font-mono text-xs text-base-content/80">${this._esc(step.target_resource)}</p>`))
    }

    if (step.target_action) {
      blocks.push(this._fieldCard('Action', `<p class="font-mono text-xs text-base-content/80">${this._esc(step.target_action)}</p>`))
    }

    if (step.side_effects?.length) {
      blocks.push(this._fieldCard(
        'Side effects',
        `<div class="flex flex-wrap gap-1">${step.side_effects.map(se => `<span class="rounded-full border border-white/10 px-2 py-1 text-[10px] text-base-content/70">${this._esc(se.type || se.name || 'effect')}</span>`).join('')}</div>`,
      ))
    }

    if (step.source_snippet) {
      blocks.push(this._fieldCard(
        'Source',
        `<pre class="overflow-x-auto whitespace-pre-wrap break-words text-xs text-base-content/80">${this._esc(step.source_snippet)}</pre>`,
      ))
    }

    panel.innerHTML = `<div class="space-y-3">${blocks.join('')}</div>`
  }

  _renderDetailsPanel(node) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const cov = typeof node.cov === 'number' ? Math.max(0, Math.min(node.cov, 100)) : 0
    const blocks = [
      this._bodyCard(`<p class="text-sm leading-6 text-base-content/85">${this._esc(node.description || 'No description')}</p>`),
      this._fieldCard(
        'Coverage',
        `
          <div class="flex items-center justify-between gap-3">
            <span class="text-xs font-semibold text-base-content">${cov}%</span>
            <button
              class="rounded-full border border-secondary/30 bg-secondary/10 px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.12em] text-secondary transition hover:border-secondary/50 hover:bg-secondary/20"
              data-show-coverage-node-id="${this._esc(node.id)}"
              type="button"
            >
              Show coverage
            </button>
          </div>
          <div class="mt-2 h-2 overflow-hidden rounded-full bg-white/8">
            <div style="width:${cov}%;height:100%;background:${covColor(cov)}"></div>
          </div>
        `,
      ),
      `
        <section class="grid gap-3 md:grid-cols-2">
          ${this._fieldCard('Domain', `<p class="text-sm text-base-content">${this._esc(node.domain || 'N/A')}</p>`)}
          ${this._fieldCard('Type', `<p class="text-sm text-base-content">${this._esc(node.type || 'unknown')}</p>`)}
        </section>
      `,
    ]

    if (node.page_route) {
      blocks.push(this._fieldCard(
        'Route',
        `<p class="font-mono text-xs text-base-content/80">${this._esc(node.page_route)}</p>`,
      ))
    }

    if (node.page_group) {
      const groupBadges = {
        anonymous: 'primary',
        player: 'success',
        operator: 'info',
        admin: 'warning',
      }
      const tone = groupBadges[node.page_group] || 'neutral'
      blocks.push(this._fieldCard(
        'Page group',
        `<span class="rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.12em]" data-step-tone="${tone}">${this._esc(node.page_group)}</span>`,
      ))
    }

    if (node.page_subtype || node.type === 'page') {
      const subtypeBadges = {
        sdui: 'info',
      }
      const subtype = node.page_subtype || 'liveview'
      const tone = subtypeBadges[subtype] || 'neutral'
      blocks.push(this._fieldCard(
        'Implementation',
        `<span class="rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.12em]" data-step-tone="${tone}">${this._esc(subtype)}</span>`,
      ))
    }

    if (node.calls_actions?.length) {
      blocks.push(this._fieldCard(
        'Called actions',
        `<div class="space-y-1">${node.calls_actions.map(action => {
          const resource = action?.resource ?? (Array.isArray(action) ? action[0] : String(action))
          const actionName = action?.action_name
          const actionType = action?.action ?? (Array.isArray(action) ? action[1] : 'unknown')
          const label = actionName ? `${resource}.${actionName}` : resource
          const badge = actionName ? actionName : actionType
          return `<p class="font-mono text-xs text-base-content/80">${this._esc(label)} <span class="text-base-content/45">(${this._esc(badge)})</span></p>`
        }).join('')}</div>`,
      ))
    }

    if (node.feature_flags?.length) {
      blocks.push(this._fieldCard(
        'Feature flags',
        `<div class="flex flex-wrap gap-1">${node.feature_flags.map(flag => `<span class="rounded-full border border-info/30 bg-info/10 px-2 py-1 font-mono text-[10px] text-info">${this._esc(flag)}</span>`).join('')}</div>`,
      ))
    }

    if (node.reqs?.length || node.compliance?.length) {
      const requirements = node.reqs || node.compliance || []

      blocks.push(this._fieldCard(
        'Compliance',
        `<div class="flex flex-wrap gap-1">${requirements.map(req => `<span class="rounded-full border border-warning/30 bg-warning/10 px-2 py-1 font-mono text-[10px] text-warning">${this._esc(req)}</span>`).join('')}</div>`,
      ))
    }

    if (node.actions?.length) {
      blocks.push(this._fieldCard(
        'Actions',
        `<div class="space-y-1">${node.actions.map(action => `<p class="font-mono text-xs text-base-content/80">${this._esc(action.name)} <span class="text-base-content/45">(${this._esc(action.type || 'unknown')})</span></p>`).join('')}</div>`,
      ))
    }

    if (node.steps?.length) {
      blocks.push(this._fieldCard(
        'Steps',
        `<div class="space-y-1">${node.steps.map(step => `<p class="font-mono text-xs text-base-content/80">${this._esc(step.name || 'unnamed')}</p>`).join('')}</div>`,
      ))
    }

    if (node.type === 'rule') {
      const relatedNodes = this._relatedRuleNodes(node)

      if (relatedNodes.length > 0) {
        blocks.push(this._fieldCard(
          'Choose node',
          `<div class="flex flex-wrap gap-2">${relatedNodes.map(relatedNode => this._relatedNodeButton(relatedNode)).join('')}</div>`,
        ))
      }
    }

    panel.innerHTML = `<div class="space-y-3">${blocks.join('')}</div>`
  }

  _renderScenarioPanel(scenario) {
    const panel = document.getElementById(SELECTORS.panelDetails)
    if (!panel) return

    const flow = Array.isArray(scenario.flow) ? scenario.flow : []
    const activeStepId = scenario.active_step_id || scenario.active_step?.id || flow[0]?.id || null
    const sections = []

    if (scenario.verified_test_command) {
      sections.push(this._fieldCard('Verified test', this._copyField(scenario.verified_test_command)))
    }

    if (scenario.compliance_links?.length) {
      sections.push(this._fieldCard(
        'Compliance',
        `<div class="flex flex-wrap gap-1">${scenario.compliance_links.map(link => `<span class="rounded-full border border-warning/30 bg-warning/10 px-2 py-1 font-mono text-[10px] text-warning">${this._esc(link)}</span>`).join('')}</div>`,
      ))
    }

    if (flow.length === 0) {
      sections.push(this._emptyState('No executable scenario flow was extracted for this scenario.'))
      panel.innerHTML = `<div class="space-y-3">${sections.join('')}</div>`
      return
    }

    sections.push(`
      <section class="space-y-2">
        ${flow.map((step, index) => this._scenarioStepCard(step, index, scenario.id, activeStepId)).join('')}
      </section>
    `)

    panel.innerHTML = `<div class="space-y-3">${sections.join('')}</div>`
  }

  _scenarioStepCard(step, index, scenarioId, activeStepId) {
    const isActive = step.id === activeStepId
    const kindLabel = formatStepKindLabel(step.kind || step.type || 'step')
    const actionName = this._displayActionName(step)
    const meta = [
      actionName ? `action ${actionName}` : null,
      this._moduleFunctionLabel(step.module_function, actionName) || null,
      step.actor || null,
      step.reacts_to || null,
    ].filter(Boolean)
    const tone = this._scenarioStepTone(step)

    return `
      <button
        class="fm-scenario-step-card w-full cursor-pointer rounded-2xl border px-3 py-3 text-left transition-all ${isActive ? 'ring-2 ring-info/25' : ''}"
        data-scenario-id="${this._esc(scenarioId)}"
        data-scenario-step-id="${this._esc(step.id)}"
        data-step-tone="${tone}"
        data-step-status="${this._esc(String(step.status || 'matched'))}"
        data-step-provenance="${this._esc(String(step.provenance || 'executed'))}"
        type="button"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0 flex-1">
            <p class="text-[10px] font-semibold uppercase tracking-[0.12em] text-base-content/35">Step ${index + 1}</p>
            <p class="mt-1 text-sm font-medium text-base-content">${this._esc(step.label || `Step ${index + 1}`)}</p>
            ${meta.length ? `<p class="mt-2 text-xs text-base-content/60">${this._esc(meta.join(' · '))}</p>` : ''}
            ${step.details ? `<p class="mt-2 break-words text-xs leading-5 text-base-content/78">${this._esc(step.details)}</p>` : ''}
          </div>
          <span class="shrink-0 rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.12em]" data-step-tone="${tone}">${this._esc(kindLabel)}</span>
        </div>
      </button>
    `
  }

  _displayActionName(step) {
    const candidates = [
      step.action_name,
      step.target_action,
      step.action,
      this._actionFromModuleFunction(step.module_function),
    ]

    return candidates
      .map(value => this._normalizeActionName(value))
      .find(value => value && value !== 'run') || null
  }

  _actionFromModuleFunction(moduleFunction) {
    if (!moduleFunction) return null
    const value = String(moduleFunction).replace(/^:/, '')
    if (value.endsWith('.run')) return null
    return value.split('.').pop()
  }

  _moduleFunctionLabel(moduleFunction, actionName) {
    if (!moduleFunction) return null
    const value = String(moduleFunction).replace(/^:/, '')
    if (value.endsWith('.run') && actionName) return null
    return value
  }

  _scenarioStepTone(step) {
    const status = String(step?.status || 'matched')
    const provenance = String(step?.provenance || 'executed')
    const kind = String(step?.kind || step?.type || 'step').replace(/^:/, '')

    if (status === 'failed') return 'failed'
    if (status === 'short_circuit') return 'warning'
    if (provenance === 'branch' || provenance === 'expanded') return 'info'
    return STEP_KIND_TONES[kind] || 'success'
  }

  _stepKindTone(kind) {
    return STEP_KIND_TONES[String(kind || 'step').replace(/^:/, '')] || 'muted'
  }

  _copyField(value) {
    return `
      <div class="flex items-center gap-2 rounded-xl border border-white/10 bg-base-300/55 px-3 py-2">
        <code class="min-w-0 flex-1 overflow-hidden text-ellipsis whitespace-nowrap text-xs text-neutral-content">${this._esc(value)}</code>
        <button class="rounded-lg border border-white/10 px-2 py-1 text-[10px] font-semibold uppercase tracking-[0.12em] text-base-content/70 transition data-[copied=true]:text-white" data-copy-value="${this._esc(value)}" data-copied="false" type="button">Copy</button>
      </div>
    `
  }

  _bodyCard(body) {
    if (!body || body.trim() === '') return ''
    return `<section class="rounded-2xl border border-white/8 bg-white/5 p-3">${body}</section>`
  }

  _fieldCard(label, body) {
    if (!body || body.trim() === '') return ''
    return `
      <section class="rounded-2xl border border-white/8 bg-white/5 p-3">
        <p class="text-[11px] font-semibold uppercase tracking-[0.12em] text-neutral-content/55">${this._esc(label)}</p>
        <div class="mt-2">${body}</div>
      </section>
    `
  }

  _emptyState(message) {
    return `
      <div class="rounded-2xl border border-dashed border-white/10 bg-white/5 px-3 py-4 text-xs text-base-content/60">
        ${this._esc(message)}
      </div>
    `
  }

  _renderActivePanel() {
    if (this._activeScenario) {
      this.renderForScenario(this._activeScenario)
      return
    }

    if (this._activeFileView?.kind === 'content') {
      this.renderFileContent(this._activeFileView)
      return
    }

    if (this._activeFileView?.kind === 'error') {
      this.renderFileError(this._activeFileView)
      return
    }

    if (this._activeNodeSelection) {
      const { nodeId, nodeData } = this._activeNodeSelection
      this.renderForNode(nodeId, nodeData)
    }
  }

  _setHeader(title, subtitle = '', { showPreview = false, previewRoute = '/' } = {}) {
    const titleEl = document.getElementById(SELECTORS.drawerTitle)
    const subtitleEl = document.getElementById(SELECTORS.drawerSubtitle)
    if (titleEl) titleEl.textContent = title || ''
    if (subtitleEl) subtitleEl.textContent = subtitle || ''

    const previewBtn = document.getElementById('fm-drawer-preview-btn')
    if (previewBtn) {
      if (showPreview) {
        previewBtn.classList.remove('hidden')
        previewBtn.dataset.startPreviewRoute = previewRoute
      } else {
        previewBtn.classList.add('hidden')
        delete previewBtn.dataset.startPreviewRoute
      }
    }
  }

  _displayNodeLabel(nodeOrId) {
    if (!nodeOrId) return ''
    if (typeof nodeOrId === 'string') return formatNodeDisplayLabel(nodeOrId)
    return nodeOrId.display_label || formatNodeDisplayLabel(nodeOrId.id)
  }

  _normalizeActionName(name) {
    if (name == null) return null
    return String(name).replace(/^:/, '')
  }

  _relatedRuleNodes(ruleNode) {
    const keys = this._ruleReferenceKeys(ruleNode)

    return [...this.normalizedNodes.values()]
      .filter(node => node.id !== ruleNode.id)
      .filter(node => (node.rules || []).some(ruleRef => keys.has(this._normalizeRuleReference(ruleRef))))
      .sort((left, right) => this._displayNodeLabel(left).localeCompare(this._displayNodeLabel(right)))
  }

  _relatedNodeButton(node) {
    return `
      <button
        class="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-medium text-base-content/80 transition hover:border-primary/30 hover:bg-primary/10 hover:text-base-content"
        data-related-node-id="${this._esc(node.id)}"
        type="button"
      >
        ${this._esc(this._displayNodeLabel(node))}
      </button>
    `
  }

  _ruleReferenceKeys(ruleNode) {
    return new Set(
      [
        ruleNode.id,
        ruleNode.display_label,
        String(ruleNode.id || '').split('.').pop(),
      ]
        .filter(Boolean)
        .map(value => this._normalizeRuleReference(value)),
    )
  }

  _normalizeRuleReference(value) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .replace(/^:+/, '')
      .replace(/[^a-z0-9]+/g, '')
  }

  _esc(value) {
    const div = document.createElement('div')
    div.textContent = value == null ? '' : String(value)
    return div.innerHTML
  }

  destroy() {
    if (this._boundCloseBtn && this._closeHandler) {
      this._boundCloseBtn.removeEventListener('click', this._closeHandler)
    }

    if (this._boundPreviewBtn && this._previewBtnHandler) {
      this._boundPreviewBtn.removeEventListener('click', this._previewBtnHandler)
    }

    if (this._boundDetailsPanel && this._detailsClickHandler) {
      this._boundDetailsPanel.removeEventListener('click', this._detailsClickHandler)
    }

    this._boundCloseBtn = null
    this._boundPreviewBtn = null
    this._boundDetailsPanel = null
    this._panel.destroy()
  }
}
