import cytoscape from 'cytoscape'
import coseBilkent from 'cytoscape-cose-bilkent'
import nodeHtmlLabel from 'cytoscape-node-html-label'

// WeakMap to prevent duplicate extension registration
const extensionRegistry = new WeakMap()

/**
 * Convert oklch or other non-hex colors to hex for Cytoscape compatibility
 */
function _colorToHex(colorStr) {
  if (!colorStr) return colorStr
  if (colorStr.startsWith('#')) return colorStr

  // Already a valid hex color
  if (colorStr.match(/^#[0-9a-f]{6}$/i)) return colorStr

  // Create temp element to convert color
  const el = document.createElement('div')
  el.style.color = colorStr
  document.body.appendChild(el)
  const computed = getComputedStyle(el).color
  document.body.removeChild(el)

  // Convert rgb(r, g, b) to hex
  const match = computed.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/)
  if (match) {
    const r = parseInt(match[1]).toString(16).padStart(2, '0')
    const g = parseInt(match[2]).toString(16).padStart(2, '0')
    const b = parseInt(match[3]).toString(16).padStart(2, '0')
    return `#${r}${g}${b}`
  }

  // Fallback: if computed color failed, try applying to background-color
  const el2 = document.createElement('div')
  el2.style.backgroundColor = colorStr
  document.body.appendChild(el2)
  const computed2 = getComputedStyle(el2).backgroundColor
  document.body.removeChild(el2)

  const match2 = computed2.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/)
  if (match2) {
    const r = parseInt(match2[1]).toString(16).padStart(2, '0')
    const g = parseInt(match2[2]).toString(16).padStart(2, '0')
    const b = parseInt(match2[3]).toString(16).padStart(2, '0')
    return `#${r}${g}${b}`
  }

  console.warn(`Failed to convert color: ${colorStr}`)
  return colorStr
}

export class CytoscapeGraph {
  constructor(container, options = {}, colors = {}) {
    this.container = container
    this.options = options
    // Convert all colors to hex for Cytoscape compatibility
    this.colors = Object.fromEntries(
      Object.entries(colors).map(([k, v]) => [k, _colorToHex(v)])
    )
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

  setupHtmlLabels(entityTpl, boundaryTpl) {
    if (this._htmlLabelsSetup) return
    this._htmlLabelsSetup = true

    this.cy.nodeHtmlLabel([
      {
        query: 'node[nodeKind="entity"]',
        halign: 'center',
        valign: 'center',
        halignBox: 'center',
        valignBox: 'center',
        tpl: entityTpl
      },
      {
        query: 'node[nodeKind="cluster"]',
        halign: 'left',
        valign: 'top',
        halignBox: 'left',
        valignBox: 'top',
        tpl: boundaryTpl
      }
    ])
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
        id: `${edge.from}->${edge.to}`,
        source: edge.from,
        target: edge.to,
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
      padding: 55,
      nodeRepulsion: 6000,
      idealEdgeLength: 80,
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
      // Domain border stripes
      {
        selector: 'node[domain="Identity"]',
        style: { 'border-color': c.gn || 'var(--fg-gn)' }
      },
      {
        selector: 'node[domain="Finance"]',
        style: { 'border-color': c.bl || 'var(--fg-bl)' }
      },
      {
        selector: 'node[domain="Compliance"]',
        style: { 'border-color': c.yw || 'var(--fg-yw)' }
      },
      {
        selector: 'node[domain="Game"]',
        style: { 'border-color': c.pu || 'var(--fg-pu)' }
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
      // Cluster/compound
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
        selector: 'edge[relation="guard"], edge[relation="eligibleIf"]',
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
