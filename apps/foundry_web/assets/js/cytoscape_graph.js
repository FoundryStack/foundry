import cytoscape from 'cytoscape'
import coseBilkent from 'cytoscape-cose-bilkent'
import nodeHtmlLabel from 'cytoscape-node-html-label'

// Global flag to prevent duplicate extension registration
let extensionsRegistered = false

const DEFAULT_LAYOUT_OPTIONS = {
  name: 'cose-bilkent',
  randomize: false,
  fit: true,
  padding: 32,
  idealEdgeLength: 62,
  nodeRepulsion: 4200,
  gravity: 0.35,
  gravityRange: 2.8,
  gravityCompound: 1.25,
  gravityRangeCompound: 1.5,
  nestingFactor: 0.18,
  packComponents: true,
  tilingPaddingHorizontal: 18,
  tilingPaddingVertical: 18,
  nodeDimensionsIncludeLabels: true,
  animate: true,
  animationDuration: 500,
}

const DEFAULT_COMPOUND_COMPACTION = {
  enabled: false,
  selector: 'node:parent',
  maxChildren: 5,
  minOccupancy: 0.32,
  spacing: 44,
  padding: 32,
}

export class CytoscapeGraph {
  constructor(container, options = {}) {
    const {
      layoutOptions = {},
      compoundCompaction = {},
      ...cyOptions
    } = options

    this.container = container
    this.cy = null
    this.currentLayout = null
    this.layoutOptions = { ...DEFAULT_LAYOUT_OPTIONS, ...layoutOptions }
    this.compoundCompaction = { ...DEFAULT_COMPOUND_COMPACTION, ...compoundCompaction }

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
      ...cyOptions,
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
    const elementCount = this.cy.elements().length
    const largeGraph = elementCount > 700
    const veryLargeGraph = elementCount > 1200

    const layoutOptions = {
      ...this.layoutOptions,
      animate: !largeGraph && this.layoutOptions.animate !== false,
      animationDuration: largeGraph ? 0 : this.layoutOptions.animationDuration,
      nodeDimensionsIncludeLabels:
        !veryLargeGraph && this.layoutOptions.nodeDimensionsIncludeLabels !== false,
    }

    this.currentLayout = this.cy.layout(layoutOptions)
    this.currentLayout.one('layoutstop', () => {
      if (!largeGraph) this._compactSparseCompoundNodes()
    })
    this.currentLayout.run()
  }

  _compactSparseCompoundNodes() {
    if (!this.compoundCompaction.enabled) return

    let compacted = false
    const parents = this.cy.nodes(this.compoundCompaction.selector)
      .sort((a, b) => b.parents().length - a.parents().length)

    if (parents.length > 80) return

    parents.forEach(parent => {
      const children = parent.children().nodes().sort((a, b) => a.id().localeCompare(b.id()))

      if (children.length < 2 || children.length > this.compoundCompaction.maxChildren) return
      if (this._compoundOccupancy(parent, children) >= this.compoundCompaction.minOccupancy) return

      const boundingBox = this._compactBoundingBox(parent, children)
      if (!boundingBox) return

      children.layout({
        name: 'grid',
        fit: false,
        animate: false,
        boundingBox,
        avoidOverlap: true,
        avoidOverlapPadding: this.compoundCompaction.spacing,
        condense: true,
        cols: Math.ceil(Math.sqrt(children.length)),
      }).run()

      compacted = true
    })

    if (compacted && this.layoutOptions.fit !== false) {
      this.cy.fit(this.cy.elements(), this.layoutOptions.padding)
    }
  }

  _compoundOccupancy(parent, children) {
    const parentBox = parent.boundingBox({ includeLabels: false, includeOverlays: false })
    const parentArea = Math.max(parentBox.w * parentBox.h, 1)

    let childArea = 0

    children.forEach(child => {
      const box = child.boundingBox({ includeLabels: false, includeOverlays: false })
      childArea += box.w * box.h
    })

    return childArea / parentArea
  }

  _compactBoundingBox(parent, children) {
    const parentBox = parent.boundingBox({ includeLabels: false, includeOverlays: false })
    const cols = Math.ceil(Math.sqrt(children.length))
    const rows = Math.ceil(children.length / cols)
    let maxWidth = 0
    let maxHeight = 0

    children.forEach(child => {
      maxWidth = Math.max(maxWidth, child.outerWidth())
      maxHeight = Math.max(maxHeight, child.outerHeight())
    })

    if (!Number.isFinite(maxWidth) || !Number.isFinite(maxHeight)) return null

    const spacing = this.compoundCompaction.spacing
    const padding = this.compoundCompaction.padding
    const width = (cols * maxWidth) + ((cols - 1) * spacing) + (padding * 2)
    const height = (rows * maxHeight) + ((rows - 1) * spacing) + (padding * 2)
    const centerX = parentBox.x1 + (parentBox.w / 2)
    const centerY = parentBox.y1 + (parentBox.h / 2)

    return {
      x1: centerX - (width / 2),
      y1: centerY - (height / 2),
      w: width,
      h: height,
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
      this.onNodeHover(evt.target.id(), evt.target.data())
    })

    this.cy.on('mouseout', 'node', (evt) => {
      this.onNodeUnhover(evt.target.id())
    })
  }
}
