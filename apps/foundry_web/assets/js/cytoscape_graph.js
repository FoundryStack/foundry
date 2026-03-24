import cytoscape from 'cytoscape'
import coseBilkent from 'cytoscape-cose-bilkent'
import nodeHtmlLabel from 'cytoscape-node-html-label'

// WeakMap to prevent duplicate extension registration
const extensionRegistry = new WeakMap()

export class CytoscapeGraph {
  constructor(container, options = {}) {
    this.container = container
    this.options = options
    this.cy = null
    this.currentLayout = null

    // Initialize callback properties with no-op defaults
    this.onNodeClick = () => {}
    this.onNodeHover = () => {}
    this.onNodeUnhover = () => {}
    this.onReady = () => {}

    // Register extensions
    cytoscape.use(coseBilkent)

    // Register nodeHtmlLabel only once per cy instance
    if (!extensionRegistry.has(this)) {
      cytoscape.use(nodeHtmlLabel)
      extensionRegistry.set(this, true)
    }

    // Create cytoscape instance
    this.cy = cytoscape({
      container: this.container,
      style: this._baseStyles(),
      layout: { name: 'null' },
      ...options
    })

    // Bind events
    this._bindEvents()
  }

  load(contextJson) {
    // Clear existing elements
    this.cy.elements().remove()

    if (!contextJson || !contextJson.nodes) {
      this.onReady()
      return
    }

    // Create domain compound parent nodes
    const domains = new Set(contextJson.nodes.map(n => n.domain).filter(Boolean))
    const domainElements = Array.from(domains).map(domain => ({
      group: 'nodes',
      data: {
        id: `domain:${domain}`,
        label: domain,
        type: 'domain',
        parent: null,
        isDomain: true
      },
      classes: 'domain-node'
    }))

    // Create node elements
    const nodeElements = contextJson.nodes.map(node => ({
      group: 'nodes',
      data: {
        id: node.id,
        label: node.id,
        type: node.type,
        domain: node.domain,
        parent: node.domain ? `domain:${node.domain}` : null,
        ...node
      }
    }))

    // Create edge elements
    const edgeElements = (contextJson.edges || []).map(edge => ({
      group: 'edges',
      data: {
        id: `${edge.source}->${edge.target}`,
        source: edge.source,
        target: edge.target,
        ...edge
      }
    }))

    // Add all elements
    this.cy.add([...domainElements, ...nodeElements, ...edgeElements])

    // Run layout
    this._runLayout()
    this.onReady()
  }

  applyDelta(delta) {
    if (!delta) return

    // Remove nodes
    if (delta.nodes_removed && delta.nodes_removed.length > 0) {
      delta.nodes_removed.forEach(id => {
        const node = this.cy.getElementById(id)
        if (node.length > 0) node.remove()
      })
    }

    // Add nodes
    if (delta.nodes_added && delta.nodes_added.length > 0) {
      const newElements = delta.nodes_added.map(node => ({
        group: 'nodes',
        data: {
          id: node.id,
          label: node.id,
          type: node.type,
          domain: node.domain,
          parent: node.domain ? `domain:${node.domain}` : null,
          ...node
        }
      }))
      this.cy.add(newElements)
    }

    // Modify nodes
    if (delta.nodes_modified && delta.nodes_modified.length > 0) {
      delta.nodes_modified.forEach(node => {
        const eleNode = this.cy.getElementById(node.id)
        if (eleNode.length > 0) {
          eleNode.data(node)
        }
      })
    }

    // Add edges
    if (delta.edges_added && delta.edges_added.length > 0) {
      const newEdges = delta.edges_added.map(edge => ({
        group: 'edges',
        data: {
          id: `${edge.source}->${edge.target}`,
          source: edge.source,
          target: edge.target,
          ...edge
        }
      }))
      this.cy.add(newEdges)
    }

    // Remove edges
    if (delta.edges_removed && delta.edges_removed.length > 0) {
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
        type: node.type,
        domain: node.domain,
        parent: node.domain ? `domain:${node.domain}` : null,
        state: 'phantom',
        ...node
      },
      classes: 'phantom-node'
    }))

    const phantomEdges = (delta.edges_added || []).map(edge => ({
      group: 'edges',
      data: {
        id: `${edge.source}->${edge.target}`,
        source: edge.source,
        target: edge.target,
        state: 'phantom',
        ...edge
      },
      classes: 'phantom-edge'
    }))

    this.cy.add([...phantomElements, ...phantomEdges])
  }

  clearProposalOverlay() {
    const phantoms = this.cy.elements().filter(ele => ele.data('state') === 'phantom')
    phantoms.remove()
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
      this.cy.animate({
        center: { eles: ele },
        zoom: 1.5,
        duration: 500
      })
    }
  }

  search(query) {
    const matches = new Set()
    this.cy.nodes().forEach(node => {
      const match = this._searchMatch(node.data(), query)
      if (match) matches.add(node.id())
    })

    this.cy.elements().forEach(ele => {
      if (ele.isNode()) {
        if (matches.has(ele.id())) {
          ele.style('opacity', 1)
        } else {
          ele.style('opacity', 0.2)
        }
      }
    })
  }

  clearSearch() {
    this.cy.elements().style('opacity', 1)
  }

  setMode(mode) {
    // Modes: 'default', 'scenario', 'authorization', 'config'
    this._applyModeStyles(mode)
  }

  destroy() {
    if (this.currentLayout) {
      this.currentLayout.stop()
    }
    if (this.cy) {
      this.cy.destroy()
      this.cy = null
    }
  }

  _bindEvents() {
    this.cy.on('tap', 'node', (evt) => {
      const node = evt.target
      if (!node.data('isDomain')) {
        this.onNodeClick(node.id(), node.data())
      }
    })

    this.cy.on('mouseover', 'node', (evt) => {
      const node = evt.target
      this.onNodeHover(node.id())
    })

    this.cy.on('mouseout', 'node', (evt) => {
      const node = evt.target
      this.onNodeUnhover(node.id())
    })
  }

  _runLayout() {
    if (this.currentLayout) {
      this.currentLayout.stop()
    }

    const layoutOptions = {
      name: 'cose-bilkent',
      nodeSeparation: 50,
      rankSeparation: 100,
      directed: false,
      animate: true,
      animationDuration: 500,
      randomize: false
    }

    this.currentLayout = this.cy.layout(layoutOptions)
    this.currentLayout.run()
  }

  _searchMatch(nodeData, query) {
    const queryLower = query.toLowerCase()
    const id = (nodeData.id || '').toLowerCase()
    const type = (nodeData.type || '').toLowerCase()
    const domain = (nodeData.domain || '').toLowerCase()

    return id.includes(queryLower) || type.includes(queryLower) || domain.includes(queryLower)
  }

  _applyModeStyles(mode) {
    // Mode-specific styling applied via CSS classes
    this.cy.elements().removeClass('scenario-hidden authorization-hidden config-hidden')

    switch (mode) {
      case 'scenario':
        // Dims non-scenario nodes (handled by FoundryGraph with context)
        break
      case 'authorization':
        // Highlights auth-related edges
        this.cy.elements().forEach(ele => {
          if (ele.isEdge() && ele.data('relation') !== 'guards') {
            ele.style('opacity', 0.2)
          }
        })
        break
      case 'config':
        // Highlights Blueprint nodes
        this.cy.nodes().forEach(node => {
          if (node.data('type') !== 'blueprint') {
            node.style('opacity', 0.3)
          }
        })
        break
      default:
        // default mode: all visible
        this.cy.elements().style('opacity', 1)
    }
  }

  _baseStyles() {
    return [
      {
        selector: 'node',
        style: {
          'content': 'data(label)',
          'text-valign': 'center',
          'text-halign': 'center',
          'width': '50px',
          'height': '50px',
          'font-size': '11px',
          'text-opacity': 1,
          'overlay-padding': '5px'
        }
      },
      {
        selector: 'node.domain-node',
        style: {
          'shape': 'round-rectangle',
          'width': 'auto',
          'height': 'auto',
          'border-width': 2,
          'text-margin-y': -10,
          'padding': '20px'
        }
      },
      {
        selector: 'node.phantom-node',
        style: {
          'border-width': 2,
          'border-style': 'dashed',
          'opacity': 0.5,
          'background-opacity': 0.5
        }
      },
      {
        selector: 'edge',
        style: {
          'target-arrow-shape': 'triangle',
          'curve-style': 'bezier',
          'width': 2
        }
      },
      {
        selector: 'node:selected',
        style: {
          'border-width': 3
        }
      }
    ]
  }
}
