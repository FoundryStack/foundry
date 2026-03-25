import { mountFoundryGraph } from '../foundry_graph'

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

      // Wire node click handler
      this.graph.onNodeClick = (nodeId, nodeData) => {
        // Below 200-module threshold: data already available
        if (contextJson.nodes.length <= 200) {
          this.pushEvent('node_selected', { id: nodeId, data: nodeData })
        } else {
          // Above threshold: fetch from server
          this.pushEvent('fetch_node_detail', { id: nodeId })
        }
      }

      // Server-pushed live reload
      this.handleEvent('graph:delta', (delta) => {
        if (this.graph) {
          this.graph.applyDelta(delta)
        }
      })

      // Server-pushed proposal overlay
      this.handleEvent('graph:proposal_overlay', (delta) => {
        if (this.graph) {
          this.graph.applyProposalOverlay(delta)
        }
      })

      // Clear proposal overlay
      this.handleEvent('graph:clear_overlay', () => {
        if (this.graph) {
          this.graph.clearProposalOverlay()
        }
      })
    } catch (error) {
      console.error('SystemMapHook init error:', error)
    }
  },

  destroyed() {
    if (this.graph) {
      this.graph.destroy()
      this.graph = null
    }
  }
}
