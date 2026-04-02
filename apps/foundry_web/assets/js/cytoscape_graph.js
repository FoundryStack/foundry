import cytoscape from 'cytoscape'
import coseBilkent from 'cytoscape-cose-bilkent'
import nodeHtmlLabel from 'cytoscape-node-html-label'
import { searchMatch } from './foundry_graph'

// Global flag to prevent duplicate extension registration
let extensionsRegistered = false

const LAYOUT_OPTIONS = {
  name: 'cose-bilkent',
  padding: 55,
  nodeRepulsion: 6000,
  idealEdgeLength: 80,
  directed: false,
  animate: true,
  animationDuration: 500,
  randomize: false,
  // Handle compound nodes better
  tile: true,
  // Increase spacing between nodes to avoid overlaps
  spacingFactor: 1.5
}

export class CytoscapeGraph {
  constructor(container, options = {}, colors = {}) {
    this.container = container
    this.options = options
    // Colors are already hex from foundry_graph.js
    this.colors = colors
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

  setupHtmlLabels(entityTpl, boundaryTpl, domainClusterTpl, stepTpl) {
    if (this._htmlLabelsSetup) return
    this._htmlLabelsSetup = true

    const templates = [
      {
        query: 'node[nodeKind="entity"]',
        halign: 'center',
        valign: 'center',
        halignBox: 'center',
        valignBox: 'center',
        tpl: entityTpl
      },
      {
        query: 'node.domain-cluster',
        halign: 'left',
        valign: 'top',
        halignBox: 'left',
        valignBox: 'top',
        tpl: domainClusterTpl
      },
      {
        query: 'node[nodeKind="cluster"]',
        halign: 'center',
        valign: 'center',
        halignBox: 'center',
        valignBox: 'center',
        tpl: boundaryTpl
      },
      {
        query: 'node[nodeKind="step"]',
        halign: 'center',
        valign: 'center',
        halignBox: 'center',
        valignBox: 'center',
        tpl: stepTpl
      }
    ]

    this.cy.nodeHtmlLabel(templates)
  }

  load(contextJson) {
    // Clear existing elements
    this.cy.elements().remove()

    if (!contextJson || !contextJson.nodes) {
      this.onReady()
      return
    }

    // NOTE: foundry_graph.js:buildCytoscapeElements() creates all nodes and compounds
    // with proper hierarchy. Elements are added directly via cy.add() in
    // mountFoundryGraph(), so this method is not actively used in current flow.

    // Create node elements (without domain compounds - they're created in buildCytoscapeElements)
    const nodeElements = contextJson.nodes.map(node => ({
      group: 'nodes',
      data: {
        id: node.id,
        label: node.id,
        type: node.type,
        domain: node.domain,
        parent: null,
        ...node
      }
    }))

    // Create edge elements
    const edgeElements = (contextJson.edges || []).map(edge => ({
      group: 'edges',
      data: {
        id: `${edge.from}->${edge.to}`,
        source: edge.from,
        target: edge.to,
        ...edge
      }
    }))

    // Add all elements
    this.cy.add([...nodeElements, ...edgeElements])

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
          id: `${edge.from}->${edge.to}`,
          source: edge.from,
          target: edge.to,
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
        id: `${edge.from}->${edge.to}`,
        source: edge.from,
        target: edge.to,
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
      const match = searchMatch(node.data(), query)
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

    this.currentLayout = this.cy.layout(LAYOUT_OPTIONS)
    this.currentLayout.run()
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
    const c = this.colors
    return [
      // Base node
      {
        selector: 'node',
        style: {
          'shape': 'round-rectangle',
          'width': 170,
          'height': 64,
          'background-color': c.base || 'var(--fg-base)',
          'border-width': 1,
          'border-color': c.b1 || 'var(--fg-b1)',
          'border-style': 'solid',
          'border-opacity': 1,
          'color': c.tx || 'var(--fg-tx)',
          'font-size': 11,
          'font-family': 'system-ui, -apple-system, sans-serif',
          'text-valign': 'center',
          'text-halign': 'center',
          'text-margin-x': 0,
          'text-margin-y': 0,
          'text-wrap': 'none',
          'padding': 6,
          'label': 'data(label)'
        }
      },
      // Hide native label for HTML-labeled nodes
      {
        selector: 'node[nodeKind="entity"], node[nodeKind="step"], node[nodeKind="state"], node[nodeKind="output"], node[nodeKind="cluster"]',
        style: { 'label': '' }
      },
      // Gap (compliance)
      {
        selector: 'node.gap',
        style: {
          'border-width': 1,
          'border-style': 'dashed',
          'border-color': c.yw || 'var(--fg-yw)'
        }
      },
      // Sensitive
      {
        selector: 'node.sensitive',
        style: {
          'border-width': 1,
          'border-color': c.rd || 'var(--fg-rd)'
        }
      },
      // Cluster/compound (base)
      {
        selector: 'node[nodeKind="cluster"]',
        style: {
          'shape': 'round-rectangle',
          'min-width': 120,
          'min-height': 60,
          'padding': 32,
          'background-color': 'rgba(20,20,35,.6)',
          'border-width': 1,
          'border-color': 'rgba(80,80,110,.3)',
          'border-style': 'dashed',
          'text-valign': 'center',
          'text-halign': 'center'
        }
      },
      // Domain cluster styling with colors
      {
        selector: 'node.domain-cluster',
        style: {
          'border-color': 'data(typeColor)',
          'border-width': 2,
          'background-color': c.base || 'var(--fg-base)',
          'background-opacity': 0.3,
          'padding': 24
        }
      },
      // Step/state nodes
      {
        selector: 'node[nodeKind="step"], node[nodeKind="state"]',
        style: {
          'width': 88,
          'height': 40,
          'font-size': 9,
          'text-valign': 'center',
          'text-halign': 'center',
          'text-wrap': 'none'
        }
      },
      // Output nodes
      {
        selector: 'node[nodeKind="output"]',
        style: {
          'width': 76,
          'height': 36,
          'font-size': 8,
          'text-valign': 'center',
          'text-halign': 'center',
          'text-wrap': 'none'
        }
      },
      // Selection
      {
        selector: 'node:selected',
        style: {
          'border-width': 1.5,
          'border-color': c.ac || 'var(--fg-ac)'
        }
      },
      // Phantom nodes
      {
        selector: 'node.phantom-node',
        style: {
          'border-width': 2,
          'border-style': 'dashed',
          'opacity': 0.5,
          'background-opacity': 0.5
        }
      },
      // Edges - base
      {
        selector: 'edge',
        style: {
          'width': 1.5,
          'line-color': c.t2 || 'var(--fg-t2)',
          'target-arrow-color': c.t2 || 'var(--fg-t2)',
          'target-arrow-shape': 'triangle',
          'curve-style': 'bezier',
          'opacity': 0.8
        }
      },
      // Edge relations
      {
        selector: 'edge[relation="sequence"]',
        style: {
          'line-color': c.t2 || 'var(--fg-t2)',
          'target-arrow-shape': 'triangle'
        }
      },
      {
        selector: 'edge[relation="async"]',
        style: {
          'line-style': 'dashed',
          'line-color': c.pu || 'var(--fg-pu)',
          'target-arrow-color': c.pu || 'var(--fg-pu)'
        }
      },
      {
        selector: 'edge[relation="guard"], edge[relation="eligibleIf"], edge[relation="guards"]',
        style: {
          'line-style': 'dotted',
          'line-color': c.yw || 'var(--fg-yw)',
          'target-arrow-color': c.yw || 'var(--fg-yw)',
          'width': 1.2
        }
      },
      {
        selector: 'edge[relation="compensation"]',
        style: {
          'width': 2,
          'line-color': c.yw || 'var(--fg-yw)',
          'target-arrow-color': c.yw || 'var(--fg-yw)'
        }
      },
      {
        selector: 'edge[relation="error"]',
        style: {
          'line-style': 'dashed',
          'line-color': c.rd || 'var(--fg-rd)',
          'target-arrow-color': c.rd || 'var(--fg-rd)'
        }
      },
      {
        selector: 'edge[relation="reads"]',
        style: {
          'line-color': c.bl || 'var(--fg-bl)',
          'target-arrow-shape': 'diamond',
          'target-arrow-fill': 'hollow'
        }
      },
      {
        selector: 'edge[relation="writes"]',
        style: {
          'line-color': c.gn || 'var(--fg-gn)',
          'target-arrow-shape': 'diamond',
          'target-arrow-fill': 'filled'
        }
      },
      {
        selector: 'edge[relation="triggers"]',
        style: {
          'line-color': c.pu || 'var(--fg-pu)',
          'target-arrow-shape': 'circle',
          'target-arrow-fill': 'filled'
        }
      },
      // New relation types from Phase A-B (data-driven edge derivation)
      {
        selector: 'edge[relation="references"]',
        style: {
          'line-color': c.b2 || 'var(--fg-b2)',
          'target-arrow-color': c.b2 || 'var(--fg-b2)',
          'target-arrow-shape': 'triangle',
          'line-style': 'solid'
        }
      },
      {
        selector: 'edge[relation="referenced_by"]',
        style: {
          'line-color': c.t2 || 'var(--fg-t2)',
          'target-arrow-color': c.t2 || 'var(--fg-t2)',
          'target-arrow-shape': 'triangle',
          'line-style': 'solid'
        }
      },
      {
        selector: 'edge[relation="configures"]',
        style: {
          'line-color': c.ac || 'var(--fg-ac)',
          'target-arrow-color': c.ac || 'var(--fg-ac)',
          'line-style': 'dashed',
          'width': 1.5,
          'opacity': 0.8
        }
      },
      {
        selector: 'edge[relation="authenticates"]',
        style: {
          'line-color': c.gn || 'var(--fg-gn)',
          'target-arrow-color': c.gn || 'var(--fg-gn)',
          'line-style': 'dashed',
          'width': 1.8
        }
      },
      {
        selector: 'edge[relation="persists_to"]',
        style: {
          'line-color': c.t3 || 'var(--fg-t3)',
          'target-arrow-color': c.t3 || 'var(--fg-t3)',
          'line-style': 'dotted',
          'width': 1
        }
      },
      {
        selector: 'edge[relation="queues_via"]',
        style: {
          'line-color': c.pu || 'var(--fg-pu)',
          'target-arrow-color': c.pu || 'var(--fg-pu)',
          'line-style': 'dotted',
          'width': 1
        }
      },
      {
        selector: 'edge[relation="calls_provider"]',
        style: {
          'line-color': c.yw || 'var(--fg-yw)',
          'target-arrow-color': c.yw || 'var(--fg-yw)',
          'line-style': 'dotted',
          'width': 1.5
        }
      },
      // External node styling
      {
        selector: 'node[type="external"]',
        style: {
          'border-style': 'dashed',
          'border-width': 1,
          'opacity': 0.7,
          'background-color': c.s3 || 'var(--bg-s3)',
          'border-color': c.t3 || 'var(--fg-t3)'
        }
      },
      // Step color coding by step_kind with white text for contrast
      {
        selector: 'node[nodeKind="step"]',
        style: {
          'color': '#ffffff'
        }
      },
      {
        selector: 'node[nodeKind="step"][step_kind="read"]',
        style: {
          'background-color': c.bl || 'var(--fg-bl)',
          'border-color': c.bl || 'var(--fg-bl)'
        }
      },
      {
        selector: 'node[nodeKind="step"][step_kind="write"]',
        style: {
          'background-color': c.gn || 'var(--fg-gn)',
          'border-color': c.gn || 'var(--fg-gn)'
        }
      },
      {
        selector: 'node[nodeKind="step"][step_kind="map"]',
        style: {
          'background-color': c.pu || 'var(--fg-pu)',
          'border-color': c.pu || 'var(--fg-pu)'
        }
      },
      {
        selector: 'node[nodeKind="step"][step_kind="custom"]',
        style: {
          'background-color': c.t2 || 'var(--fg-t2)',
          'border-color': c.t2 || 'var(--fg-t2)'
        }
      },
      // Job node: dashed border to signal scheduled/async nature
      {
        selector: 'node[type="job"]',
        style: {
          'border-style': 'dashed',
          'border-width': 1.5,
          'border-color': c.pu || 'var(--fg-pu)'
        }
      },
      // Blueprint node: diamond shape
      {
        selector: 'node[type="blueprint"]',
        style: {
          'shape': 'diamond',
          'width': 110,
          'height': 66,
          'border-color': c.ac || 'var(--fg-ac)',
          'border-width': 1
        }
      },
      // Transfer compound cluster: green border
      {
        selector: 'node[nodeKind="cluster"][type="transfer"]',
        style: {
          'border-color': c.gn || 'var(--fg-gn)',
          'border-width': 1.5
        }
      },
      // Reactor compound cluster: purple border (distinct from transfer)
      {
        selector: 'node[nodeKind="cluster"][type="reactor"]',
        style: {
          'border-color': c.pu || 'var(--fg-pu)',
          'border-width': 1.5
        }
      },
      // audit_trail edges: dotted yellow, faded — AshPaperTrail write-through
      {
        selector: 'edge[relation="audit_trail"]',
        style: {
          'line-style': 'dotted',
          'line-color': c.yw || 'var(--fg-yw)',
          'target-arrow-color': c.yw || 'var(--fg-yw)',
          'target-arrow-shape': 'triangle',
          'opacity': 0.4,
          'width': 1
        }
      },
      // Compound edge endpoints
      {
        selector: 'edge:compound',
        style: {
          'source-endpoint': 'outside-to-node',
          'target-endpoint': 'outside-to-node'
        }
      },
      // Trace
      {
        selector: '.trace',
        style: {
          'border-width': 1,
          'border-color': c.yw || 'var(--fg-yw)'
        }
      },
      {
        selector: '.trace-gap',
        style: {
          'border-width': 1,
          'border-color': c.yw || 'var(--fg-yw)'
        }
      }
    ]
  }
}
