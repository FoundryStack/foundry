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
  separateDomains: false,
  domainSelector: 'node.domain-cluster',
  domainGap: 18,
  domainLabelBufferX: 0,
  domainLabelBufferY: 0,
  domainIterations: 8,
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

  expandNode(id) {
    // System Map compounds are rendered eagerly. Selection must not mutate layout,
    // sizing, or visibility because Cytoscape compound bounds are child-driven.
    this.selectNode(id)
  }

  collapseNode(_id) {}

  expandOnly(id) {
    this.expandNode(id)
    this._expandedNodeId = id
  }

  _runLocalLayout(parentId) {
    const parent = this.cy.getElementById(parentId)
    if (parent.length === 0) return

    const children = parent.children()
    if (children.length === 0) return

    const layout = children.layout({
      name: 'grid',
      fit: false,
      boundingBox: parent.boundingBox(),
      avoidOverlap: true,
      cols: Math.ceil(Math.sqrt(children.length)),
    })
    layout.run()
  }

  _runLayout() {
    if (this.currentLayout) this.currentLayout.stop()
    this.currentLayout = this.cy.layout(this.layoutOptions)
    this.currentLayout.one('layoutstop', () => {
      const compacted = this._compactSparseCompoundNodes()
      const separated = this._separateOverlappingDomainClusters()

      if ((compacted || separated) && this.layoutOptions.fit !== false) {
        this.cy.fit(this.cy.elements(), this.layoutOptions.padding)
      }
    })
    this.currentLayout.run()
  }

  _compactSparseCompoundNodes() {
    if (!this.compoundCompaction.enabled) return false

    let compacted = false
    const parents = this.cy.nodes(this.compoundCompaction.selector)
      .sort((a, b) => b.parents().length - a.parents().length)

    parents.forEach(parent => {
      const children = parent.children().nodes().sort((a, b) => a.id().localeCompare(b.id()))

      if (children.length < 2 || children.length > this.compoundCompaction.maxChildren) return
      const isSparse = this._compoundOccupancy(parent, children) < this.compoundCompaction.minOccupancy
      const hasOverlap = this._childrenOverlap(children)
      if (!isSparse && !hasOverlap) return

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

    return compacted
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

  _childrenOverlap(children) {
    for (let i = 0; i < children.length; i += 1) {
      const a = children[i].boundingBox({ includeLabels: false, includeOverlays: false })

      for (let j = i + 1; j < children.length; j += 1) {
        const b = children[j].boundingBox({ includeLabels: false, includeOverlays: false })
        const overlapX = Math.min(a.x2, b.x2) - Math.max(a.x1, b.x1)
        const overlapY = Math.min(a.y2, b.y2) - Math.max(a.y1, b.y1)

        if (overlapX > 0 && overlapY > 0) return true
      }
    }

    return false
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

  _separateOverlappingDomainClusters() {
    if (!this.compoundCompaction.enabled || !this.compoundCompaction.separateDomains) {
      return false
    }

    const domains = this.cy.nodes(this.compoundCompaction.domainSelector)
      .sort((a, b) => a.id().localeCompare(b.id()))

    if (domains.length < 2) return false

    let separated = false
    const gap = this.compoundCompaction.domainGap
    const labelBufferX = this.compoundCompaction.domainLabelBufferX
    const labelBufferY = this.compoundCompaction.domainLabelBufferY
    const iterations = this.compoundCompaction.domainIterations

    for (let pass = 0; pass < iterations; pass += 1) {
      let movedThisPass = false

      for (let i = 0; i < domains.length; i += 1) {
        for (let j = i + 1; j < domains.length; j += 1) {
          const a = domains[i]
          const b = domains[j]
          const aBox = this._expandBox(
            a.boundingBox({ includeLabels: false, includeOverlays: false }),
            labelBufferX,
            labelBufferY,
          )
          const bBox = this._expandBox(
            b.boundingBox({ includeLabels: false, includeOverlays: false }),
            labelBufferX,
            labelBufferY,
          )
          const overlapX = Math.min(aBox.x2 + gap, bBox.x2 + gap) - Math.max(aBox.x1 - gap, bBox.x1 - gap)
          const overlapY = Math.min(aBox.y2 + gap, bBox.y2 + gap) - Math.max(aBox.y1 - gap, bBox.y1 - gap)

          if (overlapX <= 0 || overlapY <= 0) continue

          const aCenterX = aBox.x1 + (aBox.w / 2)
          const aCenterY = aBox.y1 + (aBox.h / 2)
          const bCenterX = bBox.x1 + (bBox.w / 2)
          const bCenterY = bBox.y1 + (bBox.h / 2)
          const moveX = overlapX <= overlapY ? (bCenterX >= aCenterX ? overlapX : -overlapX) : 0
          const moveY = overlapY < overlapX ? (bCenterY >= aCenterY ? overlapY : -overlapY) : 0

          this._shiftCompoundLeaves(b, moveX, moveY)
          movedThisPass = true
          separated = true
        }
      }

      if (!movedThisPass) break
    }

    return separated
  }

  _expandBox(box, padX, padY) {
    return {
      ...box,
      x1: box.x1 - padX,
      x2: box.x2 + padX,
      y1: box.y1 - padY,
      y2: box.y2 + padY,
      w: box.w + (padX * 2),
      h: box.h + (padY * 2),
    }
  }

  _shiftCompoundLeaves(parent, dx, dy) {
    parent.descendants()
      .filter(node => node.children().length === 0)
      .positions((node) => {
        const pos = node.position()
        return { x: pos.x + dx, y: pos.y + dy }
      })
  }

  _bindEvents() {
    this.cy.on('tap', 'node', (evt) => {
      const node = evt.target
      if (!node.data('isDomain')) {
        this.onNodeClick(node.id(), node.data())
      }
    })

    this.cy.on('mouseover', 'node', (evt) => {
      this.onNodeHover(evt.target.id(), evt.target.data(), evt)
    })

    this.cy.on('mouseout', 'node', (evt) => {
      this.onNodeUnhover(evt.target.id())
    })
  }
}
