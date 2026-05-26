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
  nodeRepulsion: 6500,
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
    this._coverageOverlayState = { uncoveredNodeIds: new Set() }
    this._hiddenRelations = new Set()
    this._pendingViewportFrame = null
    this._pendingViewportAction = null
    this._isReady = false

    // Initialize callback properties with no-op defaults
    this.onNodeClick = () => {}
    this.onBackgroundClick = () => {}
    this.onNodeHover = () => {}
    this.onNodeUnhover = () => {}
    this.onReady = () => {}
    this.onLayoutComplete = () => {}

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
      textureOnViewport: true,
      ...cyOptions,
    })

    this.cy.ready(() => {
      this._isReady = true
      this.onReady?.(this.cy)
    })

    this._bindEvents()
  }

  whenReady(callback) {
    this.onReady = callback

    if (this._isReady) {
      callback?.(this.cy)
    }
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
  }

  applyDelta(delta) {
    if (!delta) return

    this.cy.batch(() => {
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
    })
  }

  applyProposalOverlay(delta) {
    if (!delta) return

    if (delta.clear) {
      this.clearProposalOverlay()
      return
    }

    this.clearProposalOverlay()

    const phantomElements = (delta.nodes_added || []).map(node => ({
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

    const modifiedNodeStyles = delta.nodes_modified || []

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

    modifiedNodeStyles.forEach(node => {
      const element = this.cy.getElementById(node.id)
      if (element.length > 0) {
        element.data({ ...element.data(), proposal_state: 'modified', proposal_tone: node.tone || 'warning' })
        element.style('border-width', element.isParent() ? '3px' : '2.5px')
        element.style('border-color', '#f59e0b')
        element.style('background-color', 'rgba(245, 158, 11, 0.12)')
      }
    })
  }

  clearProposalOverlay() {
    this.cy.elements().filter(ele => ele.data('state') === 'phantom').remove()
    this.cy.elements().forEach(ele => {
      if (ele.data('proposal_state') === 'modified') {
        ele.removeData('proposal_state')
        ele.removeData('proposal_tone')
        ele.style('border-width', null)
        ele.style('border-color', null)
        ele.style('background-color', null)
      }
    })
  }

  applyCoverageOverlay({ uncovered_node_ids: uncoveredNodeIds } = {}) {
    this._coverageOverlayState = {
      uncoveredNodeIds: new Set(Array.isArray(uncoveredNodeIds) ? uncoveredNodeIds : []),
    }

    this._applyCoverageOverlayStyles()
  }

  applyScenarioStatusOverlay({ failing_node_ids: failingNodeIds = [], untraced_node_ids: untracedNodeIds = [] } = {}) {
    const failingSet = new Set(Array.isArray(failingNodeIds) ? failingNodeIds : [])
    const untracedSet = new Set(Array.isArray(untracedNodeIds) ? untracedNodeIds : [])

    this.cy.batch(() => {
      this.cy.nodes().forEach(node => {
        const id = node.id()
        const isFailing = failingSet.has(id)
        const isUntraced = untracedSet.has(id)

        if (isFailing) {
          node.addClass('scenario-failing')
        } else if (isUntraced) {
          node.addClass('scenario-untraced')
        }
      })
    })
  }

  applyScenarioOverlay({
    nodes,
    graph_path: graphPath,
    flow,
    overlay_transitions: overlayTransitions,
    overlay_edge_mode: overlayEdgeMode,
    active_step: activeStep,
    active_step_id: activeStepId,
  }) {
    if (!Array.isArray(flow) || flow.length === 0) return

    if (!this._scenarioViewportBeforeOverlay) {
      this._scenarioViewportBeforeOverlay = this._captureViewport()
    }

    this.clearScenarioOverlay({ restoreViewport: false, preserveViewportSnapshot: true })

    const currentActiveStep =
      activeStep ||
      flow.find(step => step.id === activeStepId) ||
      flow[0]

    const transitions =
      Array.isArray(overlayTransitions) && overlayTransitions.length > 0
        ? overlayTransitions
        : [...this._graphPathTransitions(graphPath), ...this._scenarioTransitions(flow)]
    const scenarioNodeIds = this._scenarioOverlayNodeIds(nodes, graphPath, flow)
    const executedNodeIds = this._scenarioStepNodeIdsByProvenance(flow, ['executed'])
    const expandedNodeIds = this._scenarioStepNodeIdsByProvenance(flow, ['expanded', 'branch'])
    const failedNodeIds = this._scenarioStepNodeIdsByStatus(flow, ['failed'])
    const shortCircuitNodeIds = this._scenarioStepNodeIdsByStatus(flow, ['short_circuit'])
    const activeNodeIds = this._scenarioActiveNodeIds(currentActiveStep)
    const activeEdgeSet = this._scenarioActiveEdges(currentActiveStep)
    const transitionEdgeSet = new Set()
    const contextNodeIds = this._scenarioContextNodeIds(scenarioNodeIds)
    const activeTone = this._scenarioStatusTone(currentActiveStep?.status)

    this.cy.batch(() => {
      this._activeScenarioOverlayMode = overlayEdgeMode || null
      this._ensureScenarioOverlayEdges(transitions, activeEdgeSet, transitionEdgeSet)

      this.cy.elements().unselect()

      this.cy.nodes().forEach(node => {
        const id = node.id()
        const isActiveFocus = activeNodeIds.has(id)
        const inScenario = scenarioNodeIds.has(id)
        const inContext = contextNodeIds.has(id)
        const isExecuted = executedNodeIds.has(id)
        const isExpandedOnly = !isExecuted && expandedNodeIds.has(id)
        const isFailed = failedNodeIds.has(id)
        const isShortCircuit = shortCircuitNodeIds.has(id)

        if (isActiveFocus) {
          node.select()
          node.style('opacity', 1)
          node.style('border-width', node.isParent() ? '3px' : '2.5px')
          node.style('border-color', activeTone.border)
          node.style('background-color', activeTone.fill)
          node.style('z-index', 999)
        } else if (isFailed) {
          node.style('opacity', 1)
          node.style('border-width', node.isParent() ? '2.5px' : '2px')
          node.style('border-color', '#dc2626')
          node.style('background-color', 'rgba(220, 38, 38, 0.12)')
          node.style('z-index', 900)
        } else if (isShortCircuit) {
          node.style('opacity', 1)
          node.style('border-width', node.isParent() ? '2.5px' : '2px')
          node.style('border-color', '#d97706')
          node.style('background-color', 'rgba(217, 119, 6, 0.1)')
          node.style('z-index', 880)
        } else if (isExecuted) {
          node.style('opacity', 1)
          node.style('border-width', node.isParent() ? '2.5px' : '2px')
          node.style('border-color', '#16a34a')
          node.style('z-index', 850)
        } else if (isExpandedOnly) {
          node.style('opacity', 0.72)
          node.style('border-width', node.isParent() ? '1.5px' : '1px')
          node.style('z-index', 820)
        } else if (inScenario || inContext) {
          node.style('opacity', 0.92)
          node.style('border-width', null)
          node.style('z-index', 800)
        } else {
          node.style('opacity', 0.12)
          node.style('z-index', null)
        }
      })

      this.cy.edges().forEach(edge => {
        const source = edge.source().id()
        const target = edge.target().id()
        const edgeKey = `${source}|${target}`
        const isScenarioEdge =
          transitionEdgeSet.has(edgeKey) ||
          transitionEdgeSet.has(`${target}|${source}`)
        const isActiveEdge = activeEdgeSet.has(edgeKey)
        const isSyntheticScenarioEdge = edge.data('state') === 'scenario-overlay'
        const overlayReason = edge.data('overlay_reason')
        const isLogicalStaticEdge = overlayReason === 'static_logical_transition'
        const touchesExecuted =
          executedNodeIds.has(source) && executedNodeIds.has(target)
        const edgeTone = this._scenarioEdgeTone(source, target, failedNodeIds, shortCircuitNodeIds)

        if (isActiveEdge) {
          edge.select()
          edge.style('line-style', 'solid')
          edge.style('width', '4px')
          edge.style('opacity', 1)
          edge.style('line-color', activeTone.line)
          edge.style('target-arrow-color', activeTone.line)
          edge.style('z-index', 999)
        } else if (isScenarioEdge) {
          edge.style(
            'line-style',
            isLogicalStaticEdge ? 'dotted' : isSyntheticScenarioEdge ? 'dashed' : 'solid',
          )
          edge.style('width', touchesExecuted ? '2.5px' : '1.5px')
          edge.style('opacity', isLogicalStaticEdge ? 0.62 : touchesExecuted ? 1 : 0.7)
          edge.style('line-color', edgeTone.line)
          edge.style('target-arrow-color', edgeTone.line)
          edge.style('z-index', 850)
        } else {
          edge.style('opacity', 0.12)
          edge.style('z-index', null)
        }
      })
    })

    this._queueViewportTransition(() => {
      const focusNodeId = this._scenarioFocusNodeId(currentActiveStep, flow, scenarioNodeIds)
      if (!focusNodeId) return

      const focusNode = this.cy.getElementById(focusNodeId)
      if (focusNode.length === 0) return

      this._centerElementsPreservingZoom(focusNode, { duration: 260 })
    })
  }

  clearScenarioOverlay({ restoreViewport = true, preserveViewportSnapshot = false } = {}) {
    this.cy.elements().filter(ele => ele.data('state') === 'scenario-overlay').remove()
    this.cy.elements().unselect()
    this._activeScenarioOverlayMode = null

    this.cy.nodes().forEach(node => {
      node.style('opacity', null)
      node.style('border-width', null)
      node.style('border-color', null)
      node.style('background-color', null)
      node.style('z-index', null)
    })

    this.cy.edges().forEach(edge => {
      edge.style('line-style', null)
      edge.style('width', null)
      edge.style('opacity', null)
      edge.style('line-color', null)
      edge.style('target-arrow-color', null)
      edge.style('z-index', null)
    })

    this._applyCoverageOverlayStyles()

    if (restoreViewport && this._scenarioViewportBeforeOverlay) {
      this._restoreViewport(this._scenarioViewportBeforeOverlay)
    }

    if (!preserveViewportSnapshot) {
      this._scenarioViewportBeforeOverlay = null
    }
  }

  _applyCoverageOverlayStyles() {
    const uncoveredNodeIds = this._coverageOverlayState?.uncoveredNodeIds || new Set()

    this.cy.nodes().forEach(node => {
      if (uncoveredNodeIds.has(node.id())) {
        node.addClass('coverage-uncovered')
      } else {
        node.removeClass('coverage-uncovered')
      }
    })
  }

  _scenarioActiveNodeIds(activeStep) {
    const ids = new Set()

    if (!activeStep) return ids

    if (activeStep.node_id) ids.add(activeStep.node_id)
    if (activeStep.node_id) ids.add(this._baseScenarioNodeId(activeStep.node_id))
    if (activeStep.focus_node_id) ids.add(activeStep.focus_node_id)
    if (activeStep.focus_node_id) ids.add(this._baseScenarioNodeId(activeStep.focus_node_id))
    ;(activeStep.focus_targets || []).forEach(id => ids.add(id))
    ;(activeStep.focus_targets || []).forEach(id => ids.add(this._baseScenarioNodeId(id)))

    return ids
  }

  _scenarioActiveEdges(activeStep) {
    const edges = new Set()
    const source = activeStep?.focus_node_id || activeStep?.node_id
    if (!source) return edges

    ;(activeStep.focus_targets || []).forEach(target => {
      if (!target || target === source) return
      edges.add(`${source}|${target}`)
    })

    return edges
  }

  _scenarioStepNodeIds(flow) {
    const ids = new Set()

    ;(flow || []).forEach(step => {
      if (step?.node_id) ids.add(step.node_id)
      if (step?.focus_node_id) ids.add(step.focus_node_id)
      ;(step?.focus_targets || []).forEach(id => {
        if (id) ids.add(id)
      })
    })

    return ids
  }

  _scenarioOverlayNodeIds(nodes, graphPath, flow) {
    const ids = new Set()

    ;(nodes || []).forEach(id => {
      if (!id) return
      ids.add(id)
      ids.add(this._baseScenarioNodeId(id))
    })

    ;(graphPath || []).forEach(id => {
      if (!id) return
      ids.add(id)
      ids.add(this._baseScenarioNodeId(id))
    })

    this._scenarioStepNodeIds(flow).forEach(id => ids.add(id))

    ids.delete(null)
    ids.delete(undefined)
    ids.delete('')

    return ids
  }

  _scenarioStepNodeIdsByProvenance(flow, provenances) {
    const allowed = new Set(provenances || [])
    const ids = new Set()

    ;(flow || []).forEach(step => {
      if (!allowed.has(step?.provenance)) return

      if (step?.node_id) ids.add(step.node_id)
      if (step?.focus_node_id) ids.add(step.focus_node_id)
      ;(step?.focus_targets || []).forEach(id => {
        if (id) ids.add(id)
      })
    })

    return ids
  }

  _scenarioStepNodeIdsByStatus(flow, statuses) {
    const allowed = new Set((statuses || []).map(status => String(status)))
    const ids = new Set()

    ;(flow || []).forEach(step => {
      if (!allowed.has(String(step?.status || ''))) return

      if (step?.node_id) ids.add(step.node_id)
      if (step?.focus_node_id) ids.add(step.focus_node_id)
      ;(step?.focus_targets || []).forEach(id => {
        if (id) ids.add(id)
      })
    })

    return ids
  }

  _scenarioTransitions(flow) {
    return (flow || []).flatMap(step => {
      const source = step.focus_node_id || step.node_id
      const targets = step.focus_targets || []

      return targets
        .filter(Boolean)
        .map(target => ({ source, target }))
        .filter(({ source: from, target: to }) => Boolean(from && to) && from !== to)
    })
  }

  _graphPathTransitions(graphPath) {
    const path = (graphPath || []).filter(Boolean)
    const transitions = []

    for (let index = 0; index < path.length - 1; index += 1) {
      const source = path[index]
      const target = path[index + 1]

      if (!(source && target) || source === target) continue
      transitions.push({ source, target })
    }

    return transitions
  }

  _scenarioContextNodeIds(nodeIds) {
    const ids = new Set(nodeIds)

    ;[...nodeIds].forEach(id => {
      const node = this.cy.getElementById(id)
      if (node.length === 0) return

      node.parents().forEach(parent => ids.add(parent.id()))
    })

    return ids
  }

  _ensureScenarioOverlayEdges(transitions, activeEdgeSet, transitionEdgeSet) {
    ;(transitions || []).forEach((transition, index) => {
      const { source, target } = transition
      if (!(source && target) || source === target) return

      // Validate both nodes exist in the graph before creating edge
      const sourceNode = this.cy.getElementById(source)
      const targetNode = this.cy.getElementById(target)
      if (sourceNode.length === 0 || targetNode.length === 0) return

      transitionEdgeSet.add(`${source}|${target}`)

      const existing = this.cy.edges().filter(edge =>
        edge.source().id() === source && edge.target().id() === target,
      )

      if (existing.length > 0) return

      const overlayId = `scenario-overlay:${index}:${source}->${target}`
      if (this.cy.getElementById(overlayId).length > 0) return

      this.cy.add({
        group: 'edges',
        data: {
          id: overlayId,
          source,
          target,
          relation: 'scenario_overlay',
          state: 'scenario-overlay',
          overlay_kind: transition.kind || 'transition',
          overlay_status: transition.status || null,
          overlay_provenance: transition.provenance || null,
          overlay_reason: transition.reason || null,
          overlay_edge_mode: this._activeScenarioOverlayMode || null,
        },
      })
    })
  }

  _baseScenarioNodeId(graphId) {
    if (!graphId || typeof graphId !== 'string') return graphId

    return graphId.split(':step:')[0].split(':action:')[0].split(':state:')[0]
  }

  _scenarioStatusTone(status) {
    switch (String(status || 'passed')) {
      case 'failed':
        return { border: '#dc2626', fill: 'rgba(220, 38, 38, 0.14)', line: '#dc2626' }
      case 'short_circuit':
        return { border: '#d97706', fill: 'rgba(217, 119, 6, 0.12)', line: '#d97706' }
      default:
        return { border: '#2563eb', fill: 'rgba(37, 99, 235, 0.1)', line: '#2563eb' }
    }
  }

  _scenarioEdgeTone(source, target, failedNodeIds, shortCircuitNodeIds) {
    if (failedNodeIds.has(source) || failedNodeIds.has(target)) {
      return { line: '#dc2626' }
    }

    if (shortCircuitNodeIds.has(source) || shortCircuitNodeIds.has(target)) {
      return { line: '#d97706' }
    }

    return { line: '#2563eb' }
  }

  _scenarioFocusNodeId(activeStep, flow, scenarioNodeIds) {
    const activeCandidates = [
      activeStep?.focus_node_id,
      activeStep?.node_id,
      ...(activeStep?.focus_targets || []),
    ].filter(Boolean)

    for (const candidate of activeCandidates) {
      if (this.cy.getElementById(candidate).length > 0) return candidate
    }

    for (const step of flow || []) {
      const stepCandidates = [
        step?.focus_node_id,
        step?.node_id,
        ...(step?.focus_targets || []),
      ].filter(Boolean)

      for (const candidate of stepCandidates) {
        if (this.cy.getElementById(candidate).length > 0) return candidate
      }
    }

    for (const candidate of scenarioNodeIds || []) {
      if (this.cy.getElementById(candidate).length > 0) return candidate
    }

    return null
  }

  selectNode(id) {
    const node = this.cy.getElementById(id)
    if (node.length > 0) {
      this.cy.elements().unselect()
      node.select()
    }
  }

  focusNode(id) {
    const node = this.cy.getElementById(id)
    if (node.length === 0) return

    this.selectNode(id)
    this._applyFocusedNeighborhood(id)
    this._queueViewportTransition(() => {
      const nextNode = this.cy.getElementById(id)
      this._centerElementsPreservingZoom(nextNode, { duration: 260 })
    })
  }

  clearSelection() {
    this.cy.elements().unselect()
    this._clearFocusedNeighborhood()
  }

  centerOn(id) {
    this._queueViewportTransition(() => {
      const ele = this.cy.getElementById(id)
      if (ele.length > 0) {
        this._centerElementsPreservingZoom(ele, { duration: 260 })
      }
    })
  }

  // Dims non-matching nodes by id set. Caller decides what matches.
  applySearchFilter(matchingIds) {
    const visibleNodes = new Set()

    this.cy.nodes().forEach(node => {
      const isTopLevelMatch = matchingIds.has(node.id()) || matchingIds.has(this._baseScenarioNodeId(node.id()))
      const parentId = node.parent()?.id()
      const isChildOfMatch = parentId && matchingIds.has(parentId)

      if (isTopLevelMatch || isChildOfMatch) {
        visibleNodes.add(node.id())
      }
    })

    this.cy.nodes('node:parent').forEach(parent => {
      const hasVisibleChild = parent.children().toArray().some(child => visibleNodes.has(child.id()))
      const isDomainCluster = parent.id().startsWith('domain:')
      const isMatchedDomain = isDomainCluster && [...visibleNodes].some(id => this.cy.getElementById(id).data('domain') === parent.data('domain'))

      if (hasVisibleChild || isMatchedDomain || matchingIds.has(parent.id())) {
        visibleNodes.add(parent.id())
      }
    })

    this.cy.nodes().forEach(node => {
      node.style('opacity', visibleNodes.has(node.id()) ? 1 : 0.16)
    })

    this.cy.edges().forEach(edge => {
      const isVisible =
        visibleNodes.has(edge.source().id()) &&
        visibleNodes.has(edge.target().id()) &&
        !this._hiddenRelations.has(edge.data('relation'))

      edge.style('opacity', isVisible ? null : 0.06)
    })
  }

  clearSearch() {
    this.cy.nodes().forEach(node => node.style('opacity', 1))
    this._applyRelationVisibility()
  }

  toggleEdgeRelation(relation) {
    if (!relation) return false

    if (this._hiddenRelations.has(relation)) {
      this._hiddenRelations.delete(relation)
    } else {
      this._hiddenRelations.add(relation)
    }

    this._applyRelationVisibility()
    return !this._hiddenRelations.has(relation)
  }

  isEdgeRelationVisible(relation) {
    return !this._hiddenRelations.has(relation)
  }

  destroy() {
    if (this.currentLayout) this.currentLayout.stop()
    this._clearPendingViewportTransition()
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

  _applyRelationVisibility() {
    this.cy.edges().forEach(edge => {
      const hidden = this._hiddenRelations.has(edge.data('relation'))
      edge.style('display', hidden ? 'none' : 'element')
      if (!hidden && edge.style('opacity') === '0.06') {
        edge.style('opacity', null)
      }
    })
  }

  _applyFocusedNeighborhood(id) {
    const activeNodeIds = new Set([id])
    const activeEdgeIds = new Set()

    this.cy.edges().forEach(edge => {
      const sourceId = edge.source().id()
      const targetId = edge.target().id()

      if (sourceId !== id && targetId !== id) return

      activeNodeIds.add(sourceId)
      activeNodeIds.add(targetId)
      activeEdgeIds.add(edge.id())
    })

    this.cy.nodes().forEach(node => {
      if (!activeNodeIds.has(node.id())) return
      node.parents().forEach(parent => activeNodeIds.add(parent.id()))
    })

    this.cy.nodes().forEach(node => {
      node.style('opacity', activeNodeIds.has(node.id()) ? 1 : 0.16)
    })

    this.cy.edges().forEach(edge => {
      edge.style('opacity', activeEdgeIds.has(edge.id()) ? null : 0.06)
    })
  }

  _clearFocusedNeighborhood() {
    this.cy.nodes().forEach(node => node.style('opacity', 1))
    this._applyRelationVisibility()
  }

  _captureViewport() {
    return {
      zoom: this.cy.zoom(),
      pan: { ...this.cy.pan() },
    }
  }

  _restoreViewport(viewport) {
    if (!viewport) return

    this.cy.stop()
    this.cy.animate({
      zoom: viewport.zoom,
      pan: viewport.pan,
      duration: 320,
    })
  }

  _getSidebarOffset() {
    const raw = getComputedStyle(document.documentElement)
      .getPropertyValue('--foundry-sidebar-width').trim()
    const width = parseInt(raw, 10)
    return Number.isFinite(width) ? width / 2 : 120
  }

  _centerElementsPreservingZoom(elements, { duration = 260 } = {}) {
    if (!elements || elements.length === 0) return

    const zoom = this.cy.zoom()
    const bb = elements.boundingBox()
    const sidebarOffset = this._getSidebarOffset()
    const panX = (this.cy.width() / 2) + sidebarOffset - (bb.x1 + bb.w / 2) * zoom
    const panY = (this.cy.height() / 2) - (bb.y1 + bb.h / 2) * zoom

    if (this._isViewportClose({ x: panX, y: panY }, zoom)) return

    this.cy.stop()
    this.cy.animate({ pan: { x: panX, y: panY }, duration })
  }

  _focusElements(elements, { padding = 96, maxZoom = 1, minZoom = 0.35, duration = 320 } = {}) {
    if (!elements || elements.length === 0) return

    const viewport = this.cy.getFitViewport(elements, padding)

    if (!viewport) {
      this.cy.animate({ fit: { eles: elements, padding }, duration })
      return
    }

    const zoom = Math.max(minZoom, Math.min(maxZoom, viewport.zoom))
    const sidebarOffset = this._getSidebarOffset()
    const pan = { x: viewport.pan.x + sidebarOffset, y: viewport.pan.y }

    if (this._isViewportClose(pan, zoom)) return

    this.cy.stop()
    this.cy.animate({
      pan,
      zoom,
      duration,
    })
  }

  _queueViewportTransition(callback, { settleFrames = 2 } = {}) {
    if (typeof callback !== 'function') return

    this._pendingViewportAction = callback
    this._clearPendingViewportTransition()

    let remainingFrames = settleFrames
    const tick = () => {
      if (!this.cy) return

      if (remainingFrames > 0) {
        remainingFrames -= 1
        this._pendingViewportFrame = requestAnimationFrame(tick)
        return
      }

      this._pendingViewportFrame = null
      const action = this._pendingViewportAction
      this._pendingViewportAction = null
      action?.()
    }

    this._pendingViewportFrame = requestAnimationFrame(tick)
  }

  _clearPendingViewportTransition() {
    if (this._pendingViewportFrame) {
      cancelAnimationFrame(this._pendingViewportFrame)
      this._pendingViewportFrame = null
    }
  }

  _isViewportClose(nextPan, nextZoom, panTolerance = 1, zoomTolerance = 0.01) {
    const currentPan = this.cy.pan()
    const currentZoom = this.cy.zoom()

    return (
      Math.abs(currentPan.x - nextPan.x) <= panTolerance &&
      Math.abs(currentPan.y - nextPan.y) <= panTolerance &&
      Math.abs(currentZoom - nextZoom) <= zoomTolerance
    )
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
      if (compacted) this.cy.nodes('node:parent').updateCompoundBounds(true)
      const separated = this._separateOverlappingDomainClusters()

      if ((compacted || separated) && this.layoutOptions.fit !== false) {
        this._focusElements(this.cy.elements(), { padding: this.layoutOptions.padding, duration: 0 })
      }

      // Signal that layout is complete
      this.onLayoutComplete?.()
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

      if (children.length < 2) return

      const hasOverlap = this._childrenOverlap(children)
      const oversized = children.length > this.compoundCompaction.maxChildren
      const isSparse = !oversized && this._compoundOccupancy(parent, children) < this.compoundCompaction.minOccupancy

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
          const overlapX = Math.min(aBox.x2, bBox.x2) - Math.max(aBox.x1, bBox.x1) + gap
          const overlapY = Math.min(aBox.y2, bBox.y2) - Math.max(aBox.y1, bBox.y1) + gap

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

    this.cy.on('tap', (evt) => {
      if (evt.target === this.cy) {
        this.onBackgroundClick()
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
