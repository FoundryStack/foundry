import { mountFoundryGraph, covColor, domainCoverage, searchMatch } from '../foundry_graph'

const SELECTORS = {
  sidebarList: 'fm-sidebar-list',
  search: 'fm-search',
  drawer: 'fm-drawer',
  drawerClose: 'fm-drawer-close',
  hoverCard: 'fm-hover-card',
  panelDetails: 'fm-panel-details',
  panelFlow: 'fm-panel-flow',
  panelActions: 'fm-panel-actions',
  panelAuth: 'fm-panel-auth'
}

const CONFIG = {
  drawerWidth: '380px',
  nodeThreshold: 200,
  searchDebounce: 150
}

export const SystemMapHook = {
  mounted() {
    try {
      // Ensure DOM is ready before accessing styles
      if (document.readyState !== 'complete' && document.readyState !== 'interactive') {
        setTimeout(() => this._initGraph(), 0)
        return
      }
      this._initGraph()
    } catch (error) {
      console.error('SystemMapHook mount error:', error)
    }
  },

  _initGraph() {
    try {
      const contextJson = JSON.parse(this.el.dataset.context)
      this.graph = mountFoundryGraph(this.el, contextJson)

      // Cache for normalized nodes
      this.normalizedNodes = this.graph.normalizedNodes

      // Initialize UI
      this._initSidebar()
      this._initDrawer()
      this._initSearch()

      // Wire node click handler
      this.graph.onNodeClick = (nodeId, nodeData) => {
        // Below threshold: data already available
        if (contextJson.nodes.length <= CONFIG.nodeThreshold) {
          this.pushEvent('node_selected', { id: nodeId, data: nodeData })
          this._handleNodeSelected(nodeId)
        } else {
          // Above threshold: fetch from server
          this.pushEvent('fetch_node_detail', { id: nodeId })
        }
      }

      // Wire hover handler
      this.graph.onNodeHover = (nodeId) => {
        this._showHoverCard(nodeId)
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

      // Node detail from server (>200 modules)
      this.handleEvent('node_detail', (payload) => {
        if (payload.node) {
          this._handleNodeSelected(payload.node.id)
        }
      })
    } catch (error) {
      console.error('SystemMapHook init error:', error)
    }
  },

  _initSidebar() {
    const list = document.getElementById(SELECTORS.sidebarList)
    if (!list) return

    // Sidebar item click delegation
    this._sidebarClickHandler = (evt) => {
      const item = evt.target.closest('[data-node-id]')
      if (item) {
        const nodeId = item.dataset.nodeId
        this.graph.selectNode(nodeId)
        this.graph.centerOn(nodeId)
        this._handleNodeSelected(nodeId)
      }
    }
    list.addEventListener('click', this._sidebarClickHandler)
  },

  _initSearch() {
    const searchInput = document.getElementById(SELECTORS.search)
    if (!searchInput) return

    this._searchInputHandler = (evt) => {
      clearTimeout(this._searchTimeout)
      const query = evt.target.value.trim()

      this._searchTimeout = setTimeout(() => {
        const list = document.getElementById(SELECTORS.sidebarList)
        if (!list) return

        const items = list.querySelectorAll('[data-node-id]')
        items.forEach(item => {
          const nodeId = item.dataset.nodeId
          const node = this.normalizedNodes.get(nodeId)

          if (!node) {
            item.style.display = 'none'
            return
          }

          const match = searchMatch(node, query)
          item.style.display = match ? '' : 'none'
        })
      }, CONFIG.searchDebounce)
    }
    searchInput.addEventListener('input', this._searchInputHandler)
  },

  _initDrawer() {
    const drawer = document.getElementById(SELECTORS.drawer)
    const closeBtn = document.getElementById(SELECTORS.drawerClose)

    if (!closeBtn) return

    this._closeHandler = () => {
      drawer.style.width = '0'
    }
    closeBtn.addEventListener('click', this._closeHandler)

    // Tab click delegation
    const tabs = drawer.querySelectorAll('[data-tab]')
    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        this._switchTab(tab.dataset.tab)
      })
    })
  },

  _switchTab(tabName) {
    const drawer = document.getElementById(SELECTORS.drawer)
    const tabs = drawer.querySelectorAll('[data-tab]')
    const panels = {
      details: document.getElementById(SELECTORS.panelDetails),
      flow: document.getElementById(SELECTORS.panelFlow),
      actions: document.getElementById(SELECTORS.panelActions),
      auth: document.getElementById(SELECTORS.panelAuth)
    }

    // Deactivate all tabs
    tabs.forEach(t => t.classList.remove('tab-active'))

    // Activate clicked tab
    drawer.querySelector(`[data-tab="${tabName}"]`).classList.add('tab-active')

    // Hide all panels
    Object.values(panels).forEach(p => {
      if (p) p.classList.add('hidden')
    })

    // Show active panel
    if (panels[tabName]) {
      panels[tabName].classList.remove('hidden')
    }
  },

  _handleNodeSelected(nodeId) {
    const node = this.normalizedNodes.get(nodeId)
    if (!node) return

    // Highlight sidebar item
    const list = document.getElementById(SELECTORS.sidebarList)
    if (list) {
      list.querySelectorAll('[data-node-id]').forEach(item => {
        item.classList.toggle('active', item.dataset.nodeId === nodeId)
      })
    }

    // Open drawer
    const drawer = document.getElementById(SELECTORS.drawer)
    if (drawer) {
      drawer.style.width = CONFIG.drawerWidth
    }

    // Render panels
    this._renderDetailsPanel(node)
    this._renderFlowPanel(node)
    this._renderActionsPanel(node)
    this._renderAuthPanel(node)

    // Switch to Details tab
    this._switchTab('details')
  },

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

    // Compliance requirements
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

    // FSM states
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

    // Steps
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

    // Routes
    if (n.routes && n.routes.length > 0) {
      html += `
        <div>
          <div class="text-xs text-base-content/50 mb-1">Routes (${n.routes.length})</div>
        </div>
      `
    }

    // Flags
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

    // Runbook
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
  },

  _renderFlowPanel(n) {
    const panel = document.getElementById(SELECTORS.panelFlow)
    if (!panel) return

    // Scenarios not yet tracked
    panel.innerHTML = `
      <div class="text-center py-6">
        <p class="text-xs text-base-content/50">No scenarios defined yet</p>
      </div>
    `
  },

  _renderActionsPanel(n) {
    const panel = document.getElementById(SELECTORS.panelActions)
    if (!panel) return

    const shortcuts = {
      resource: ['Edit schema', 'View migrations', 'Test coverage'],
      transfer: ['View pipeline', 'Trace execution', 'Replay'],
      reactor: ['Run simulation', 'Debug', 'Test coverage'],
      rule: ['View conditions', 'Test rule', 'Audit log'],
      liveview: ['Open in browser', 'View live metrics', 'Test coverage']
    }

    const actions = shortcuts[n.type] || ['Open details', 'View in codebase']

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
  },

  _renderAuthPanel(node) {
    const panel = document.getElementById(SELECTORS.panelAuth)
    if (!panel) return

    // Only show for resource nodes
    if (node.type !== 'resource') {
      panel.innerHTML = '<p class="text-xs text-base-content/50">N/A for this node type</p>'
      return
    }

    panel.innerHTML = `
      <div class="text-xs text-base-content/50">
        <p>Authorization data not yet available</p>
      </div>
    `
  },

  _showHoverCard(nodeId) {
    const node = this.normalizedNodes.get(nodeId)
    if (!node) return

    const card = document.getElementById(SELECTORS.hoverCard)
    if (!card) return

    const coverage = domainCoverage([node])
    const cov = coverage.length > 0 ? coverage[0].avg : node.cov

    card.innerHTML = `
      <div class="font-semibold text-xs mb-1">${this._esc(node.id)}</div>
      <div class="text-xs text-base-content/60">${this._esc(node.domain || 'N/A')}</div>
      <div class="flex items-center gap-2 mt-1">
        <div class="w-8 bg-base-300 rounded h-1">
          <div style="width: ${cov}%; height: 100%; background: ${covColor(cov)}"></div>
        </div>
        <span class="text-xs">${cov}%</span>
      </div>
      ${node.reqs && node.reqs.length > 0 ? `
        <div class="text-xs text-warning mt-1">⚠ ${node.reqs.length} compliance req${node.reqs.length > 1 ? 's' : ''}</div>
      ` : ''}
    `

    card.classList.remove('hidden')

    // Position near cursor (done by CSS in real implementation)
    card.style.left = '8px'
    card.style.top = '8px'
  },

  _hideHoverCard() {
    const card = document.getElementById(SELECTORS.hoverCard)
    if (card) {
      card.classList.add('hidden')
    }
  },

  _esc(s) {
    const div = document.createElement('div')
    div.textContent = s
    return div.innerHTML
  },

  destroyed() {
    // Remove event listeners
    const list = document.getElementById(SELECTORS.sidebarList)
    if (list && this._sidebarClickHandler) {
      list.removeEventListener('click', this._sidebarClickHandler)
    }

    const searchInput = document.getElementById(SELECTORS.search)
    if (searchInput && this._searchInputHandler) {
      searchInput.removeEventListener('input', this._searchInputHandler)
      clearTimeout(this._searchTimeout)
    }

    const closeBtn = document.getElementById(SELECTORS.drawerClose)
    if (closeBtn && this._closeHandler) {
      closeBtn.removeEventListener('click', this._closeHandler)
    }

    if (this.graph) {
      this.graph.destroy()
      this.graph = null
    }
  }
}
