import cytoscape from 'cytoscape'
import coseBilkent from 'cytoscape-cose-bilkent'
import nodeHtmlLabel from 'cytoscape-node-html-label'

// Global flag to prevent duplicate extension registration
let extensionsRegistered = false

const LAYOUT_OPTIONS = {
  name: 'cose-bilkent',
  randomize: false,
  fit: true,
  padding: 55,
  idealEdgeLength: 80,
  nodeRepulsion: 6000,
  nodeDimensionsIncludeLabels: true,
  animate: true,
  animationDuration: 500,
}

export class CytoscapeGraph {
  constructor(container, options = {}) {
    this.container = container
    this.cy = null
    this.currentLayout = null

    // Initialize callback properties with no-op defaults
    this.onNodeClick = () => {}
    this.onNodeHover = () => {}
    this.onNodeUnhover = () => {}
    this.onReady = () => {}

    // Register extensions once globally
    if (!extensionsRegistered) {
      cytoscape.use(coseBilkent)
      cytoscape.use(nodeHtmlLabel)
      extensionsRegistered = true
    }

    // Caller provides the stylesheet via options.style.
    // CytoscapeGraph has no opinion about what the graph looks like.
    this.cy = cytoscape({
      container: this.container,
      style: [],
      layout: { name: 'null' },
      ...options,
    })

    this._bindEvents()
  }

  setupHtmlLabels(templates) {
    if (this._htmlLabelsSetup) return
    this._htmlLabelsSetup = true
    this.cy.nodeHtmlLabel(templates)
  }

  load(contextJson) {
    this.cy.elements().remove()

    if (!contextJson || !contextJson.nodes) {
      this.onReady()
      return
    }

    const nodeElements = contextJson.nodes.map(node => ({
      group: 'nodes',
      data: { id: node.id, label: node.id, ...node },
    }))

    const edgeElements = (contextJson.edges || []).map(edge => ({
      group: 'edges',
      data: {
        id: `${edge.from}->${edge.to}`,
        source: edge.from,
        target: edge.to,
        ...edge,
      },
    }))

    this.cy.add([...nodeElements, ...edgeElements])
    this._runLayout()
    this.onReady()
  }

  applyDelta(delta) {
    if (!delta) return

    if (delta.nodes_removed?.length > 0) {
      delta.nodes_removed.forEach(id => {
        const node = this.cy.getElementById(id)
        if (node.length > 0) node.remove()
      })
    }

    if (delta.nodes_added?.length > 0) {
      const newElements = delta.nodes_added.map(node => ({
        group: 'nodes',
        data: {
          id: node.id,
          label: node.id,
          parent: node.domain ? `domain:${node.domain}` : null,
          ...node,
        },
      }))
      this.cy.add(newElements)
    }

    if (delta.nodes_modified?.length > 0) {
      delta.nodes_modified.forEach(node => {
        const ele = this.cy.getElementById(node.id)
        if (ele.length > 0) ele.data(node)
      })
    }

    if (delta.edges_added?.length > 0) {
      const newEdges = delta.edges_added.map(edge => ({
        group: 'edges',
        data: {
          id: `${edge.from}->${edge.to}`,
          source: edge.from,
          target: edge.to,
          ...edge,
        },
      }))
      this.cy.add(newEdges)
    }

    if (delta.edges_removed?.length > 0) {
      delta.edges_removed.forEach(id => {
        const edge = this.cy.getElementById(id)
        if (edge.length > 0) edge.remove()
      })
    }
  }

  applyProposalOverlay(delta) {
    if (!delta || !delta.nodes_added) return

    const phantomElements = delta.nodes_added.map(node => ({
      group: 'nodes',
      data: {
        id: node.id,
        label: `${node.id} [proposed]`,
        parent: node.domain ? `domain:${node.domain}` : null,
        state: 'phantom',
        ...node,
      },
      classes: 'phantom-node',
    }))

    const phantomEdges = (delta.edges_added || []).map(edge => ({
      group: 'edges',
      data: {
        id: `${edge.from}->${edge.to}`,
        source: edge.from,
        target: edge.to,
        state: 'phantom',
        ...edge,
      },
      classes: 'phantom-edge',
    }))

    this.cy.add([...phantomElements, ...phantomEdges])
  }

  clearProposalOverlay() {
    this.cy.elements().filter(ele => ele.data('state') === 'phantom').remove()
  }

  selectNode(id) {
    const node = this.cy.getElementById(id)
    if (node.length > 0) {
      this.cy.elements().unselect()
      node.select()
    }
  }

  clearSelection() {
    this.cy.elements().unselect()
  }

  centerOn(id) {
    const ele = this.cy.getElementById(id)
    if (ele.length > 0) {
      this.cy.animate({ center: { eles: ele }, zoom: 1.5, duration: 500 })
    }
  }

  // Dims non-matching nodes by id set. Caller decides what matches.
  applySearchFilter(matchingIds) {
    this.cy.nodes().forEach(node => {
      node.style('opacity', matchingIds.has(node.id()) ? 1 : 0.2)
    })
  }

  clearSearch() {
    this.cy.elements().style('opacity', 1)
  }

  destroy() {
    if (this.currentLayout) this.currentLayout.stop()
    if (this.cy) {
      this.cy.destroy()
      this.cy = null
    }
  }

  _runLayout() {
    if (this.currentLayout) this.currentLayout.stop()
    this.currentLayout = this.cy.layout(LAYOUT_OPTIONS)
    this.currentLayout.run()
  }

  _bindEvents() {
    this.cy.on('tap', 'node', (evt) => {
      const node = evt.target
      if (!node.data('isDomain')) {
        this.onNodeClick(node.id(), node.data())
      }
    })

    this.cy.on('mouseover', 'node', (evt) => {
      this.onNodeHover(evt.target.id())
    })

    this.cy.on('mouseout', 'node', (evt) => {
      this.onNodeUnhover(evt.target.id())
    })
  }
}