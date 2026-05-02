import { mountFoundryGraph, covColor, getActionTypeColor, getTypeColor } from '../foundry_graph'
import { UI_CONFIG } from '../graph/config'
import { DrawerManager } from './system_map/drawer_manager'
import { SidebarManager } from './system_map/sidebar_manager'

export const SystemMapHook = {
  mounted() {
    try {
      this._restoreSizes()

      if (document.readyState !== 'complete' && document.readyState !== 'interactive') {
        setTimeout(() => this._initGraph(), 0)
        return
      }
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

  _restoreSizes() {
    const sidebar = document.getElementById('fm-sidebar')
    if (sidebar) {
      const sidebarWidth = parseInt(localStorage.getItem(UI_CONFIG.storageKeys.sidebarWidth)) || UI_CONFIG.sidebarWidth.default
      sidebar.style.width = `${sidebarWidth}px`
    }

    const drawer = document.getElementById('fm-drawer')
    if (drawer) {
      const drawerWidth = parseInt(localStorage.getItem(UI_CONFIG.storageKeys.drawerWidth)) || UI_CONFIG.drawerWidth.default
      if (drawer.classList.contains('open')) {
        drawer.style.width = `${drawerWidth}px`
      }
    }
  },

  _initGraph() {
    try {
      const contextJson = JSON.parse(this.el.dataset.context)
      this.graph = mountFoundryGraph(this.el, contextJson)

      // Initialize managers
      this.drawer = new DrawerManager(this.graph.normalizedNodes)
      this.sidebar = new SidebarManager(this.graph, this.graph.normalizedNodes)

      // Wire sidebar node select callback
      this.sidebar.onNodeSelect = (nodeId) => {
        const nodeData = this.graph.normalizedNodes.get(nodeId)
        this._handleNodeSelected(nodeId, nodeData)
        this.pushEvent('node_selected', { id: nodeId })
      }

      // Wire node click handler
      this.graph.onNodeClick = (nodeId, nodeData) => {
        if (contextJson.nodes.length <= UI_CONFIG.nodeThreshold) {
          this.pushEvent('node_selected', { id: nodeId, data: nodeData })
          this._handleNodeSelected(nodeId, nodeData)
        } else {
          this.pushEvent('fetch_node_detail', { id: nodeId })
        }
      }

      // Wire hover handler
      this.graph.onNodeHover = (nodeId, nodeData, event) => {
        this._showHoverCard(nodeId, nodeData, event)
      }

      this.graph.onNodeUnhover = () => {
        this._hideHoverCard()
      }

      // Server-pushed events
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

      this.handleEvent('graph:clear_overlay', () => {
        if (this.graph) {
          this.graph.clearProposalOverlay()
        }
      })

      this.handleEvent('node_detail', (payload) => {
        if (payload.node) {
          this._handleNodeSelected(payload.node.id, payload.node)
        }
      })
    } catch (error) {
      console.error('SystemMapHook init error:', error)
    }
  },

  _handleNodeSelected(nodeId, nodeData = null) {
    this.sidebar.highlightNode(nodeId)
    this.drawer.open()
    this.drawer.renderForNode(nodeId, nodeData)
    this.graph.expandOnly(nodeId)
  },

  _showHoverCard(nodeId, nodeData = null, event = null) {
    const node = this._resolveHoverNode(nodeId, nodeData)
    if (!node) return

    const card = document.getElementById('fm-hover-card')
    if (!card) return

    const cov = typeof node.cov === 'number' ? node.cov : 0
    const gap = !!(node.compliance_gap ?? node.gap)
    const reqs = node.reqs || []
    const coverageLabel = gap ? 'compliance coverage gap' : 'covered'
    const typeColor = node.typeColor || getTypeColor(node.type)
    const typeLabel = node.type === 'agent' ? 'agent step' : node.type

    card.innerHTML = `
      <div class="fm-hover-header">
        <span class="fm-hover-type" style="color:${this._esc(typeColor)};border-color:${this._esc(typeColor)}">${this._esc(typeLabel || 'node')}</span>
        ${node.sensitive ? '<span class="fm-hover-sensitive">sensitive</span>' : ''}
      </div>
      <div class="fm-hover-name">${this._esc(node.name || node.id || nodeId)}</div>
      <div class="fm-hover-row">
        <span class="fm-hover-key">domain</span>
        <span class="fm-hover-value">${this._esc(node.domain || 'N/A')}</span>
      </div>
      ${node.parentName ? `
        <div class="fm-hover-row">
          <span class="fm-hover-key">parent</span>
          <span class="fm-hover-value">${this._esc(node.parentName)}</span>
        </div>
      ` : ''}
      ${node.showCoverage !== false ? `
        <div class="fm-hover-coverage">
          <div class="fm-hover-bar">
            <div class="fm-hover-fill" style="width:${cov}%;background:${covColor(cov)}"></div>
          </div>
          <span>${cov}% ${coverageLabel}</span>
        </div>
        <div class="fm-hover-row">
          <span class="fm-hover-key">compliance</span>
          <span class="fm-hover-value ${gap ? 'is-gap' : 'is-covered'}">${gap ? 'coverage gap' : 'covered'}</span>
        </div>
      ` : ''}
      ${node.rows.length > 0 ? `
        <div class="fm-hover-separator"></div>
        ${node.rows.map(row => `
          <div class="fm-hover-row">
            <span class="fm-hover-key">${this._esc(row.label)}</span>
            <span class="fm-hover-value">${this._esc(row.value)}</span>
          </div>
        `).join('')}
      ` : ''}
      ${reqs.length > 0 ? `
        <div class="fm-hover-separator"></div>
        <div class="fm-hover-pills">
          ${reqs.slice(0, 4).map(req => `<span class="fm-hover-pill">${this._esc(req)}</span>`).join('')}
          ${reqs.length > 4 ? `<span class="fm-hover-pill">+${reqs.length - 4}</span>` : ''}
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
      name: node.name || node.label || node.id || nodeId,
      type: node.type || node.nodeKind || 'node',
      typeColor: node.typeColor || getTypeColor(node.type),
      domain: node.domain,
      cov: typeof node.cov === 'number' ? node.cov : 0,
      gap: !!(node.compliance_gap ?? node.gap),
      compliance_gap: !!(node.compliance_gap ?? node.gap),
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

  updated() {
    try {
      this._restoreSizes()
    } catch (error) {
      console.error('SystemMapHook update error:', error)
    }
  },

  destroyed() {
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

    if (this.graph) {
      this.graph.destroy()
      this.graph = null
    }
  }
}
