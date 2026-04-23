import { mountFoundryGraph, covColor, domainCoverage } from '../foundry_graph'
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
    } catch (error) {
      console.error('SystemMapHook mount error:', error)
    }
  },

  _restoreSizes() {
    const layout = document.querySelector('.foundry-map-layout')
    if (layout) {
      const sidebarWidth = parseInt(localStorage.getItem(UI_CONFIG.storageKeys.sidebarWidth)) || UI_CONFIG.sidebarWidth.default
      layout.style.gridTemplateColumns = `${sidebarWidth}px 1fr`
    }

    const drawer = document.getElementById('fm-drawer')
    if (drawer && drawer.offsetWidth > 0) {
      const drawerWidth = parseInt(localStorage.getItem(UI_CONFIG.storageKeys.drawerWidth)) || UI_CONFIG.drawerWidth.default
      drawer.style.width = `${drawerWidth}px`
    }
  },

  _initGraph() {
    try {
      const contextJson = JSON.parse(this.el.dataset.context)
      this.graph = mountFoundryGraph(this.el, contextJson)

      // Initialize managers
      this.drawer = new DrawerManager(this.graph.normalizedNodes)
      this.sidebar = new SidebarManager(this.graph, this.graph.normalizedNodes)

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
      this.graph.onNodeHover = (nodeId, nodeData) => {
        this._showHoverCard(nodeId, nodeData)
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

  _showHoverCard(nodeId, nodeData = null) {
    const node = this.graph.normalizedNodes.get(nodeId) || nodeData
    if (!node) return

    const card = document.getElementById('fm-hover-card')
    if (!card) return

    const coverage = (typeof node.cov === 'number') ? domainCoverage([node]) : []
    const cov = coverage.length > 0 ? coverage[0].avg : (typeof node.cov === 'number' ? node.cov : 0)

    card.innerHTML = `
      <div class="font-semibold text-xs mb-1">${this._esc(node.id || nodeId)}</div>
      <div class="text-xs text-base-content/60">${this._esc(node.domain || 'N/A')}</div>
      <div class="flex items-center gap-2 mt-1">
        <div class="w-8 bg-base-300 rounded h-1">
          <div style="width: ${cov || 0}%; height: 100%; background: ${covColor(cov || 0)}"></div>
        </div>
        <span class="text-xs">${cov || 0}%</span>
      </div>
      ${node.reqs && node.reqs.length > 0 ? `
        <div class="text-xs text-warning mt-1">⚠ ${node.reqs.length} compliance req${node.reqs.length > 1 ? 's' : ''}</div>
      ` : ''}
    `

    card.classList.remove('hidden')
    card.style.left = '8px'
    card.style.top = '8px'
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

  updated() {
    try {
      this._restoreSizes()
    } catch (error) {
      console.error('SystemMapHook update error:', error)
    }
  },

  destroyed() {
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
