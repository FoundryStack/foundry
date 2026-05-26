import { mountFoundryGraph, covColor, getActionTypeColor, getTypeColor } from '../foundry_graph'
import { requestGraphLoaderDismiss } from './graph_loader_hook'
import {
  formatNodeDisplayLabel,
  getComplianceStatus,
  getTypeDisplayLabel,
  shouldShowComplianceIndicator,
} from '../graph/semantics'
import { UI_CONFIG } from '../graph/config'
import { DrawerManager } from './system_map/drawer_manager'
import { FeedManager } from './system_map/feed_manager'
import { SidebarManager } from './system_map/sidebar_manager'

export const SystemMapHook = {
  mounted() {
    try {
      this.feed = new FeedManager()
      this._initGraph()

      // Register keyboard shortcut for feed toggle (⌘\)
      this._keyHandler = (e) => {
        if ((e.metaKey || e.ctrlKey) && e.key === '\\') {
          e.preventDefault()
          this.pushEvent('toggle_feed', {})
        }
      }
      document.addEventListener('keydown', this._keyHandler)
    } catch (error) {
      console.error('SystemMapHook mount error:', error)
    }
  },

  _initGraph() {
    try {
      const contextJson = JSON.parse(this.el.dataset.context)
      this._previewBaseUrl = this.el.dataset.previewBaseUrl || 'http://localhost:4001'
      this.graph = mountFoundryGraph(this.el, contextJson)
      this.graph.whenReady(() => {
        this._wireGraphInteractions(contextJson)
      })

      // Wire layout complete callback to dismiss the graph loader overlay
      this.graph.onLayoutComplete = () => {
        requestGraphLoaderDismiss()
      }
    } catch (error) {
      console.error('SystemMapHook init error:', error)
    }

    this._syncCoverageOverlay()
    this._syncUiState()
    this._startUiObservers()
  },

  _wireGraphInteractions(contextJson) {
    if (this._graphInteractionsBound) return
    this._graphInteractionsBound = true

    const pushEvent = (event, payload) => {
      this.pushEvent(event, payload)
    }
    this.drawer = new DrawerManager(this.graph.normalizedNodes, pushEvent, {
      onNodeSelect: nodeId => {
        const nodeData = this.graph.normalizedNodes.get(nodeId)
        this._selectNode(nodeId, nodeData, { pushSelection: true })
      },
      onStartPreview: (route) => {
        this._startPreview(route)
      },
    })
    this.sidebar = new SidebarManager(this.graph, this.graph.normalizedNodes)

    this.sidebar.onNodeSelect = (nodeId) => {
      const nodeData = this.graph.normalizedNodes.get(nodeId)
      this._selectNode(nodeId, nodeData, { pushSelection: true })
    }

    this.graph.onNodeClick = (nodeId, nodeData) => {
      const resolvedNodeData = nodeData || this.graph.normalizedNodes.get(nodeId)

      this._selectNode(nodeId, resolvedNodeData, { pushSelection: true })

      if (contextJson.nodes.length > UI_CONFIG.nodeThreshold) {
        this.pushEvent('fetch_node_detail', { id: nodeId })
      }
    }

    this.graph.onBackgroundClick = () => {
      if (this._isCoverageMode()) {
        this.pushEvent('clear_node_filter', {})
      }

      this.pushEvent('clear_scenario', {})
    }

    this.graph.onNodeHover = (nodeId, nodeData, event) => {
      this._showHoverCard(nodeId, nodeData, event)
    }

    this.graph.onNodeUnhover = () => {
      this._hideHoverCard()
    }

    this.handleEvent('graph:delta', (delta) => {
      if (this.graph) {
        this.graph.applyDelta(delta)
      }
    })

    this.handleEvent('graph:proposal_overlay', (delta) => {
      if (this.graph) {
        this.graph.applyProposalOverlay(delta)
      }
    })

    this.handleEvent('graph:scenario_overlay', (payload) => {
      if (this.graph) {
        try {
          this.graph.applyScenarioOverlay(payload)
        } catch (e) {
          console.error('  ❌ applyScenarioOverlay error:', e)
        }
      }

      if (this.drawer) {
        this.drawer.renderForScenario(payload)
      }
    })

    this.handleEvent('graph:coverage_overlay', (payload) => {
      if (this.graph) {
        this.graph.applyCoverageOverlay(payload)
      }
    })

    this.handleEvent('graph:scenario_status_overlay', (payload) => {
      if (this.graph) {
        this.graph.applyScenarioStatusOverlay(payload)
      }
    })

    this.handleEvent('drawer:open_flow', () => {
      this.drawer?.open()
    })

    this.handleEvent('graph:clear_overlay', () => {
      if (this.graph) {
        this.graph.clearScenarioOverlay()
      }

      if (this.sidebar) {
        this.sidebar.clearHighlight()
      }

      if (this.drawer) {
        this.drawer.clearScenario()
      }
    })

    this.handleEvent('node_detail', (payload) => {
      if (payload.node) {
        this._hydrateNodeDetail(payload.node)
      }
    })

    this.handleEvent('file_content', (payload) => {
      this.drawer.open()
      this.drawer.renderFileContent(payload)
    })

    this.handleEvent('proposal_file_preview', (payload) => {
      this.drawer.open()
      this.drawer.renderProposalFilePreview(payload)
    })

    this.handleEvent('file_error', (payload) => {
      this.drawer.open()
      this.drawer.renderFileError(payload)
    })
  },

  _handleNodeSelected(nodeId, nodeData = null) {
    this.sidebar.highlightNode(nodeId)
    this.drawer.open()
    this.drawer.renderForNode(nodeId, nodeData)
    this.graph.focusNode(nodeId)
  },

  _selectNode(nodeId, nodeData = null, { pushSelection = false } = {}) {
    if (nodeData) {
      this.graph.normalizedNodes.set(nodeId, nodeData)
    }

    this._selectedNodeId = nodeId
    this._handleNodeSelected(nodeId, nodeData)

    if (pushSelection) {
      this.pushEvent(this._selectionEventName(), { id: nodeId, data: nodeData })
    }
  },

  _hydrateNodeDetail(nodeData) {
    if (!nodeData?.id) return

    this.graph.normalizedNodes.set(nodeData.id, nodeData)

    if (this._selectedNodeId === nodeData.id) {
      this.sidebar.highlightNode(nodeData.id)
      this.drawer.open()
      this.drawer.renderForNode(nodeData.id, nodeData)
    }
  },

  _startPreview(route = '/') {
    const previewTargetUrl = this._buildPreviewTargetUrl(route)
    const launchUrl = new URL('/preview-launch', window.location.origin)
    launchUrl.searchParams.set('target', previewTargetUrl)
    this._openPreviewLaunch(launchUrl.toString())
  },

  _buildPreviewTargetUrl(route = '/') {
    const base = this._previewBaseUrl || 'http://localhost:4001'
    const normalizedRoute = this._normalizePreviewRoute(route)
    // In cloud mode, base is a path prefix like "/preview-app" — resolve relative
    // to the current page origin rather than treating it as an absolute URL.
    if (base.startsWith('/')) {
      const prefix = base.replace(/\/$/, '')
      const suffix = normalizedRoute.startsWith('/') ? normalizedRoute : `/${normalizedRoute}`
      return prefix + suffix
    }
    return new URL(normalizedRoute, base).toString()
  },

  _normalizePreviewRoute(route = '/') {
    if (typeof route !== 'string') return '/'

    const trimmedRoute = route.trim()

    if (trimmedRoute === '' || trimmedRoute === 'undefined' || trimmedRoute === 'null') {
      return '/'
    }

    return trimmedRoute.startsWith('/') ? trimmedRoute : `/${trimmedRoute}`
  },

  async _openPreviewLaunch(launchUrl) {
    if (this._isTauriRuntime()) {
      try {
        await this._openExternalUrl(launchUrl)
        return
      } catch (error) {
        console.error('SystemMapHook preview opener error:', error)
      }
    }

    window.open(launchUrl, '_blank')
  },

  _isTauriRuntime() {
    return !!(window.__TAURI_INTERNALS__ || window.__TAURI__)
  },

  async _openExternalUrl(url) {
    if (window.__TAURI_INTERNALS__?.invoke) {
      await window.__TAURI_INTERNALS__.invoke('plugin:opener|open_url', { url })
      return
    }

    if (window.__TAURI__?.core?.invoke) {
      await window.__TAURI__.core.invoke('plugin:opener|open_url', { url })
      return
    }

    throw new Error('Tauri opener API unavailable')
  },

  _showHoverCard(nodeId, nodeData = null, event = null) {
    const node = this._resolveHoverNode(nodeId, nodeData)
    if (!node) return

    const card = document.getElementById('fm-hover-card')
    if (!card) return

    const cov = typeof node.cov === 'number' ? node.cov : 0
    const reqs = node.reqs || []
    const complianceStatus = getComplianceStatus(reqs, node.test_coverage || {})
    const gap = !!(node.compliance_gap ?? node.gap)
    const coverageLabel = 'test coverage'
    const typeColor = node.typeColor || getTypeColor(node.type)
    const typeLabel = getTypeDisplayLabel(node)
    const showCompliance = shouldShowComplianceIndicator(node)

    card.innerHTML = `
      <div class="mb-1 flex items-center justify-between gap-1.5">
        <span class="rounded-full border px-1.5 py-0.5 text-[11px] leading-[1.4]" style="color:${this._esc(typeColor)};border-color:${this._esc(typeColor)};background:var(--fg-s3)">${this._esc(typeLabel || 'node')}</span>
        ${node.sensitive ? '<span class="rounded-full border border-[var(--fg-rd)] bg-[var(--fg-s3)] px-1.5 py-0.5 text-[11px] leading-[1.4] text-[var(--fg-rd)]">sensitive</span>' : ''}
      </div>
      <div class="mb-1.5 break-words font-mono text-[13px] font-semibold">
        ${this._esc(node.name || node.id || nodeId)}
      </div>
      <div class="mt-0.5 flex items-center justify-between gap-2">
        <span class="uppercase tracking-[0.04em] text-[color:color-mix(in_oklch,var(--color-base-content)_55%,transparent)]">domain</span>
        <span class="break-words text-right text-[var(--color-base-content)]">${this._esc(node.domain || 'N/A')}</span>
      </div>
      ${node.parentName ? `
        <div class="mt-0.5 flex items-center justify-between gap-2">
          <span class="uppercase tracking-[0.04em] text-[color:color-mix(in_oklch,var(--color-base-content)_55%,transparent)]">parent</span>
          <span class="break-words text-right text-[var(--color-base-content)]">${this._esc(node.parentName)}</span>
        </div>
      ` : ''}
      ${node.showCoverage !== false ? `
        <div class="my-1.5 flex items-center gap-1.5 text-[var(--fg-t2)]">
          <div class="h-1 min-w-12 flex-1 overflow-hidden rounded-full bg-[var(--fg-s3)]">
            <div class="h-full rounded-[inherit]" style="width:${cov}%;background:${covColor(cov)}"></div>
          </div>
          <span>${cov}% ${coverageLabel}</span>
        </div>
        ${showCompliance ? `
          <div class="mt-0.5 flex items-center justify-between gap-2">
            <span class="uppercase tracking-[0.04em] text-[color:color-mix(in_oklch,var(--color-base-content)_55%,transparent)]">compliance</span>
            <span class="break-words text-right ${gap ? 'text-[var(--fg-yw)]' : 'text-[var(--fg-gn)]'}">${this._esc(complianceStatus.label)}</span>
          </div>
        ` : ''}
      ` : ''}
      ${node.rows.length > 0 ? `
        <div class="my-1.5 h-px bg-[var(--fg-b2)]"></div>
        ${node.rows.map(row => `
          <div class="mt-0.5 flex items-center justify-between gap-2">
            <span class="uppercase tracking-[0.04em] text-[color:color-mix(in_oklch,var(--color-base-content)_55%,transparent)]">${this._esc(row.label)}</span>
            <span class="break-words text-right text-[var(--color-base-content)]">${this._esc(row.value)}</span>
          </div>
        `).join('')}
      ` : ''}
      ${reqs.length > 0 ? `
        <div class="my-1.5 h-px bg-[var(--fg-b2)]"></div>
        <div class="flex flex-wrap items-center gap-1.5">
          ${reqs.slice(0, 4).map(req => `<span class="rounded-full border border-[var(--fg-b2)] bg-[var(--fg-s3)] px-1.5 py-0.5 font-mono text-[11px] leading-[1.4] text-[var(--fg-ac)]">${this._esc(req)}</span>`).join('')}
          ${reqs.length > 4 ? `<span class="rounded-full border border-[var(--fg-b2)] bg-[var(--fg-s3)] px-1.5 py-0.5 font-mono text-[11px] leading-[1.4] text-[var(--fg-ac)]">+${reqs.length - 4}</span>` : ''}
        </div>
      ` : ''}
    `

    card.classList.remove('hidden')
    this._positionHoverCard(card, event)
  },

  _resolveHoverNode(nodeId, nodeData = null) {
    const normalized = this.graph.normalizedNodes

    const stepMatch = nodeId.match(/^(.+):step:(\d+)$/)
    if (stepMatch) {
      const [, parentId, stepIdx] = stepMatch
      const parent = normalized.get(parentId)
      const step = parent?.steps?.[parseInt(stepIdx)]
      if (!parent || !step) return this._baseHoverNode(nodeId, nodeData)

      const stepKind = this._normalizeActionName(step.step_kind || step.type || 'step')
      const isAgent = stepKind === 'agent' || !!step.agent
      const sideEffects = step.side_effects || []
      const rows = [
        { label: 'kind', value: stepKind || 'step' },
        step.target_resource ? { label: 'resource', value: step.target_resource } : null,
        step.target_action ? { label: 'action', value: step.target_action } : null,
        step.wait_for?.length > 0 ? { label: 'wait for', value: step.wait_for.join(', ') } : null,
        sideEffects.length > 0 ? { label: 'side effects', value: this._sideEffectSummary(sideEffects) } : null,
      ].filter(Boolean)

      return {
        ...this._parentHoverContext(parent),
        id: nodeId,
        name: step.name || `Step ${stepIdx}`,
        type: isAgent ? 'agent' : 'step',
        typeColor: getTypeColor(isAgent ? 'agent' : 'step'),
        parentName: parent.id,
        showCoverage: false,
        rows,
      }
    }

    const actionMatch = nodeId.match(/^(.+):action:(.+)$/)
    if (actionMatch) {
      const [, parentId, rawActionName] = actionMatch
      const parent = normalized.get(parentId)
      const actionName = this._normalizeActionName(rawActionName)
      const action =
        (parent?.actions || []).find(a => this._normalizeActionName(a.name) === actionName) ||
        { name: actionName, type: nodeData?.action_type, description: nodeData?.description }

      if (!parent) return this._baseHoverNode(nodeId, nodeData)

      const transitions = (parent.sm?.transitions || []).filter(t => this._normalizeActionName(t.action) === actionName)
      const actionType = this._normalizeActionName(action.type || nodeData?.action_type || 'action')
      const rows = [
        { label: 'action type', value: actionType },
        transitions.length > 0 ? { label: 'transitions', value: transitions.map(t => `${t.from} -> ${t.to}`).join(', ') } : { label: 'transitions', value: 'none' },
      ]

      return {
        ...this._parentHoverContext(parent),
        id: nodeId,
        name: action.name || actionName,
        type: 'action',
        typeColor: getActionTypeColor(actionType),
        parentName: parent.id,
        showCoverage: false,
        rows,
      }
    }

    const stateMatch = nodeId.match(/^(.+):state:(.+)$/)
    if (stateMatch) {
      const [, parentId, rawStateName] = stateMatch
      const parent = normalized.get(parentId)
      if (!parent) return this._baseHoverNode(nodeId, nodeData)

      const stateName = rawStateName
      const outgoing = (parent.sm?.transitions || []).filter(t => t.from === stateName)
      const incoming = (parent.sm?.transitions || []).filter(t => t.to === stateName)

      return {
        ...this._parentHoverContext(parent),
        id: nodeId,
        name: stateName,
        type: 'state',
        typeColor: getTypeColor('state'),
        parentName: parent.id,
        showCoverage: false,
        rows: [
          { label: 'incoming', value: `${incoming.length}` },
          { label: 'outgoing', value: `${outgoing.length}` },
        ],
      }
    }

    const node = normalized.get(nodeId) || nodeData
    return this._baseHoverNode(nodeId, node)
  },

  _baseHoverNode(nodeId, node = null) {
    if (!node) return null
    return {
      id: node.id || nodeId,
      name: node.name || node.label || node.display_label || formatNodeDisplayLabel(node.id || nodeId),
      type: node.type || node.nodeKind || 'node',
      typeColor: node.typeColor || getTypeColor(node.type),
      domain: node.domain,
      cov: typeof node.cov === 'number' ? node.cov : 0,
      gap: !!(node.compliance_gap ?? node.gap),
      compliance_gap: !!(node.compliance_gap ?? node.gap),
      has_compliance_links: !!(node.has_compliance_links ?? ((node.reqs || []).length > 0)),
      sensitive: !!node.sensitive,
      reqs: node.reqs || [],
      showCoverage: true,
      rows: [
        node.runbook ? { label: 'runbook', value: node.runbook } : null,
        node.sm?.states?.length > 0 ? { label: 'states', value: `${node.sm.states.length}` } : null,
        node.actions?.length > 0 ? { label: 'actions', value: `${node.actions.length}` } : null,
      ].filter(Boolean),
    }
  },

  _parentHoverContext(parent) {
    return {
      domain: parent.domain,
      showCoverage: false,
    }
  },

  _sideEffectSummary(sideEffects) {
    const declared = sideEffects.filter(se => se.declared).length
    const inferred = sideEffects.length - declared
    if (declared > 0 && inferred > 0) return `${declared} declared, ${inferred} inferred`
    if (declared > 0) return `${declared} declared`
    return `${inferred} inferred`
  },

  _positionHoverCard(card, event = null) {
    const original = event?.originalEvent
    const boundsEl = card.parentElement || this.el
    const rect = boundsEl.getBoundingClientRect()

    if (!original) {
      card.style.left = '10px'
      card.style.top = '10px'
      return
    }

    let left = original.clientX - rect.left + 14
    let top = original.clientY - rect.top - 10

    if (left + 280 > rect.width) {
      left = original.clientX - rect.left - 290
    }

    if (top + 300 > rect.height) {
      top = rect.height - 310
    }

    card.style.left = `${Math.max(10, left)}px`
    card.style.top = `${Math.max(10, top)}px`
  },

  _hideHoverCard() {
    const card = document.getElementById('fm-hover-card')
    if (card) {
      card.classList.add('hidden')
    }
  },

  _esc(s) {
    const div = document.createElement('div')
    div.textContent = s
    return div.innerHTML
  },

  _normalizeActionName(name) {
    if (name == null) return null
    return String(name).replace(/^:/, '')
  },

  _syncCoverageOverlay() {
    if (!this.graph) return

    const metadata = document.getElementById('system-map-metadata')
    if (!metadata) return

    try {
      const uncoveredNodeIds = JSON.parse(metadata.dataset.uncoveredNodeIds || '[]')
      this.graph.applyCoverageOverlay({ uncovered_node_ids: uncoveredNodeIds })
    } catch (error) {
      console.error('SystemMapHook coverage sync error:', error)
    }
  },

  _metadata() {
    return document.getElementById('system-map-metadata')
  },

  _currentSidebarTab() {
    return this._metadata()?.dataset.sidebarTab || 'system_map'
  },

  _isCoverageMode() {
    return this._currentSidebarTab() === 'test_coverage'
  },

  _selectionEventName() {
    return this._isCoverageMode() ? 'show_node_coverage' : 'node_selected'
  },

  _startUiObservers() {
    if (this._uiMutationObserver) {
      this._uiMutationObserver.disconnect()
    }

    if (typeof MutationObserver !== 'function') return

    const observer = new MutationObserver(() => {
      this.sidebar?.sync()
      this._syncCoverageOverlay()
      this._syncUiState()
    })

    const sidebar = document.getElementById('fm-sidebar')
    if (sidebar) {
      observer.observe(sidebar, { childList: true, subtree: true })
    }

    const metadata = this._metadata()
    if (metadata) {
      observer.observe(metadata, {
        attributes: true,
        attributeFilter: ['data-sidebar-tab', 'data-selected-node-id', 'data-uncovered-node-ids'],
      })
    }

    this._uiMutationObserver = observer
  },

  _syncUiState() {
    const metadata = this._metadata()
    const selectedNodeId = metadata?.dataset.selectedNodeId
    const currentSidebarTab = this._currentSidebarTab()
    const tabChanged = this._lastSyncedSidebarTab !== currentSidebarTab
    const selectionChanged = this._lastSyncedSelectedNodeId !== selectedNodeId

    if (this.sidebar && !this.sidebar.hasBoundList()) {
      this.sidebar.sync()
    }

    if (selectedNodeId) {
      this._selectedNodeId = selectedNodeId
      this.sidebar?.highlightNode(selectedNodeId)

      if (currentSidebarTab === 'system_map' && (tabChanged || selectionChanged)) {
        this.graph?.focusNode(selectedNodeId)
      }

      this._lastSyncedSidebarTab = currentSidebarTab
      this._lastSyncedSelectedNodeId = selectedNodeId
      return
    }

    if (currentSidebarTab === 'system_map') {
      this.graph?.clearSelection()
      this.sidebar?.clearHighlight()
    }

    this._lastSyncedSidebarTab = currentSidebarTab
    this._lastSyncedSelectedNodeId = null
  },

  updated() {
    try {
      this.feed?.sync()
      this.drawer?.sync()
      this.sidebar?.sync()
      this._syncCoverageOverlay()
      this._syncUiState()
    } catch (error) {
      console.error('SystemMapHook update error:', error)
    }
  },

  destroyed() {
    if (this._uiMutationObserver) {
      this._uiMutationObserver.disconnect()
      this._uiMutationObserver = null
    }

    if (this._keyHandler) {
      document.removeEventListener('keydown', this._keyHandler)
      this._keyHandler = null
    }

    if (this.drawer) {
      this.drawer.destroy()
      this.drawer = null
    }

    if (this.sidebar) {
      this.sidebar.destroy()
      this.sidebar = null
    }

    if (this.feed) {
      this.feed.destroy()
      this.feed = null
    }

    if (this.graph) {
      this.graph.destroy()
      this.graph = null
    }
  }
}
