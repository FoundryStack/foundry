import { normalizeActionName, normalizeActionType, buildStateNodeId, buildActionNodeId } from './normalizers'
import { getDomainColor } from './colors'
import { shortLabel } from './templates'

export function getCompoundNodeIds(nodes) {
  const transfers = nodes.filter(n => n.type === 'transfer' || n.type === 'reactor').map(n => n.id)
  const resourcesWithChildren = nodes
    .filter(n => n.type === 'resource' && (n.sm || (n.actions || []).length > 0))
    .map(n => n.id)

  return new Set([...transfers, ...resourcesWithChildren])
}

export function getTransferNodeIds(nodes) {
  return new Set(nodes.filter(n => n.type === 'transfer' || n.type === 'reactor').map(n => n.id))
}

export function getFsmResourceIds(nodes) {
  return new Set(nodes.filter(n => n.type === 'resource' && n.sm).map(n => n.id))
}

export function consolidateExternalNodes(nodes) {
  const edgeMap = {}
  const seen = new Set()
  const result = []

  for (const n of nodes) {
    if (n.type === 'external') {
      const match = n.id.match(/^(external:[^:]+):/)
      if (match) {
        const collapsedId = match[1]
        edgeMap[n.id] = collapsedId
        if (!seen.has(collapsedId)) {
          seen.add(collapsedId)
          result.push({ ...n, id: collapsedId, label: collapsedId.replace('external:', '') })
        }
        continue
      }
    }
    result.push(n)
  }

  return { nodes: result, edgeMap }
}

export function buildResourceActionIndex(nodes) {
  const actionIndex = new Map()

  nodes
    .filter(node => node.type === 'resource')
    .forEach(resource => {
      const actionNames = new Set()

      ;(resource.actions || []).forEach(action => {
        const actionName = normalizeActionName(action.name)
        if (actionName) {
          actionNames.add(actionName)
        }
      })

      actionIndex.set(resource.id, actionNames)
    })

  return actionIndex
}

export function buildCollapsedBehaviorPairs(edges, nodeById, stepScopedNodeTypes, behavioralRelations) {
  const activeStepsByOwner = new Map()
  const stepsByPair = new Map()

  edges.forEach(edge => {
    if (!behavioralRelations.has(edge.relation)) return
    if (normalizeActionName(edge.action_name)) return

    const owner = getStepScopedOwner(edge, nodeById, stepScopedNodeTypes)
    if (!owner) return

    const stepIndex = typeof edge.step_index === 'number' ? edge.step_index : null
    if (stepIndex === null) return

    addSetValue(activeStepsByOwner, owner.ownerId, stepIndex)
    addSetValue(stepsByPair, pairKey(owner.ownerId, owner.peerId), stepIndex)
  })

  const collapsedPairs = new Set()

  stepsByPair.forEach((pairSteps, key) => {
    const [ownerId] = key.split('\u0000')
    const activeSteps = activeStepsByOwner.get(ownerId)

    if (!activeSteps || activeSteps.size <= 1) return
    if (pairSteps.size !== activeSteps.size) return

    const coversAllActiveSteps = [...activeSteps].every(stepIndex => pairSteps.has(stepIndex))

    if (coversAllActiveSteps) {
      collapsedPairs.add(key)
    }
  })

  return collapsedPairs
}

export function buildCytoscapeElements(nodes, edges) {
  const elements = []
  const behavioralRelations = new Set(['reads', 'writes'])

  const { nodes: consolidatedNodes, edgeMap: externalEdgeMap } = consolidateExternalNodes(nodes)
  nodes = consolidatedNodes

  // Domain cluster compounds
  const domains = new Set(nodes.map(n => n.domain).filter(Boolean))
  domains.forEach(domain => {
    elements.push({
      group: 'nodes',
      data: {
        id: `domain:${domain}`,
        label: domain,
        nodeKind: 'cluster',
        domain,
        typeColor: getDomainColor(domain),
      },
      classes: 'domain-cluster',
    })
  })

  const compoundIds = getCompoundNodeIds(nodes)
  const stepScopedNodeTypes = new Set(['reactor', 'transfer'])
  const nodeById = new Map(nodes.map(node => [node.id, node]))
  const resourceActionIndex = buildResourceActionIndex(nodes)
  const collapsedBehaviorPairs = buildCollapsedBehaviorPairs(
    edges,
    nodeById,
    stepScopedNodeTypes,
    behavioralRelations,
  )

  // Transfer / FSM compound nodes (now IS the entity)
  compoundIds.forEach(id => {
    const node = nodes.find(n => n.id === id)
    if (!node) return
    const classes = [
      node.type === 'transfer' ? 'transfer-cluster' : null,
      node.type === 'reactor' ? 'transfer-cluster' : null,
      node.sm ? 'fsm-cluster' : null,
      node.gap ? 'gap' : null,
      node.sensitive ? 'sensitive' : null,
    ].filter(Boolean).join(' ')

    elements.push({
      group: 'nodes',
      data: {
        ...node,
        id: node.id,
        label: shortLabel(node.id),
        nodeKind: 'cluster',
        parent: node.domain ? `domain:${node.domain}` : null,
      },
      classes,
    })
  })

  // Entity nodes — only for non-compound nodes
  nodes.forEach(node => {
    if (compoundIds.has(node.id)) return

    const parent = node.domain ? `domain:${node.domain}` : null

    const classes = [
      node.gap       ? 'gap'       : null,
      node.sensitive ? 'sensitive' : null,
    ].filter(Boolean).join(' ')

    elements.push({
      group: 'nodes',
      data: { id: node.id, nodeKind: 'entity', parent, ...node },
      classes,
    })
  })

  // Step / action / state child nodes
  nodes.forEach(node => {
    if ((node.type === 'transfer' || node.type === 'reactor') && node.steps) {
      node.steps.forEach((step, idx) => {
        const stepKind = (step.step_kind || '').toString().replace(/^:/, '')
        const icons = { read: '📖', write: '✏', map: '◈' }
        const stepLabel = `${icons[stepKind] || '⚙'} ${step.name || `Step ${idx}`}`

        const sideEffects = step.side_effects || []
        elements.push({
          group: 'nodes',
          data: {
            id: `${node.id}:step:${idx}`,
            label: stepLabel,
            nodeKind: 'step',
            parent: node.id,
            step_kind: stepKind,
            description: step.description || step.name || `Step ${idx}`,
            type: node.type,
            domain: node.domain,
            side_effects: sideEffects,
            has_declared_se: sideEffects.some(se => se.declared) ? 'true' : 'false',
            has_inferred_se: sideEffects.some(se => !se.declared) ? 'true' : 'false',
          },
        })
      })

      if (node.steps.length > 1) {
        node.steps.forEach((_, idx) => {
          if (idx === 0) return
          elements.push({
            group: 'edges',
            data: {
              id: `${node.id}:seq:${idx}`,
              source: `${node.id}:step:${idx - 1}`,
              target: `${node.id}:step:${idx}`,
              relation: 'sequence',
            },
          })
        })
      }
    }

    if (node.type === 'resource' && node.actions) {
      node.actions.forEach((action, idx) => {
        const actionName = normalizeActionName(action.name || `action_${idx}`)
        const actionType = normalizeActionType(action.type || 'read')

        elements.push({
          group: 'nodes',
          data: {
            id: buildActionNodeId(node.id, actionName),
            label: actionName,
            nodeKind: 'action',
            parent: node.id,
            action_name: actionName,
            action_type: actionType,
            description: action.description || `${actionName} action`,
            type: node.type,
            domain: node.domain,
          },
        })
      })
    }

    if (node.sm?.states) {
      node.sm.states.forEach(state => {
        elements.push({
          group: 'nodes',
          data: {
            id: state.id,
            label: state.name,
            nodeKind: 'state',
            parent: node.id,
          },
        })
      })
    }

    if (node.sm?.transitions) {
      node.sm.transitions.forEach((transition, idx) => {
        const fromStateId = buildStateNodeId(node.id, transition.from)
        const toStateId = buildStateNodeId(node.id, transition.to)
        const actionName = normalizeActionName(transition.action)
        const actionNodeId = resolveResourceActionEndpoint(node.id, actionName, resourceActionIndex)

        if (actionNodeId) {
          elements.push({
            group: 'edges',
            data: {
              id: `${node.id}:eligible:${idx}:${transition.from}:${actionName}`,
              source: fromStateId,
              target: actionNodeId,
              relation: 'eligibleIf',
              action_name: actionName,
            },
          })

          elements.push({
            group: 'edges',
            data: {
              id: `${node.id}:trigger:${idx}:${actionName}:${transition.to}`,
              source: actionNodeId,
              target: toStateId,
              relation: 'triggers',
              action_name: actionName,
            },
          })
        } else {
          elements.push({
            group: 'edges',
            data: {
              id: `${node.id}:transition:${idx}:${transition.from}:${transition.to}`,
              source: fromStateId,
              target: toStateId,
              relation: 'triggers',
              action_name: actionName,
            },
          })
        }
      })
    }
  })

  // Edges
  const edgeElementsById = new Map()

  edges.forEach(edge => {
    const routed = routeEdgeEndpoints(
      edge,
      nodeById,
      resourceActionIndex,
      externalEdgeMap,
      stepScopedNodeTypes,
      collapsedBehaviorPairs,
      behavioralRelations,
    )
    const source = routed.source
    const target = routed.target
    if (source === target) return

    const id = `${source}->${target}:${edge.relation}`
    const existing = edgeElementsById.get(id)

    if (existing) {
      mergeRoutedEdge(existing.data, edge, routed)
      return
    }

    edgeElementsById.set(id, {
      group: 'edges',
      data: buildRoutedEdgeData(id, source, target, edge, routed),
    })
  })

  elements.push(...edgeElementsById.values())

  return elements
}

function routeEdgeEndpoints(
  edge,
  nodeById,
  resourceActionIndex,
  externalEdgeMap,
  stepScopedNodeTypes,
  collapsedBehaviorPairs,
  behavioralRelations,
) {
  let source = externalEdgeMap[edge.from] || edge.from
  let target = externalEdgeMap[edge.to] || edge.to
  const stepIndex = typeof edge.step_index === 'number' ? edge.step_index : null
  const actionName = normalizeActionName(edge.action_name)
  const sourceActionId = resolveResourceActionEndpoint(edge.from, actionName, resourceActionIndex)
  const targetActionId = resolveResourceActionEndpoint(edge.to, actionName, resourceActionIndex)
  const actionRouted = Boolean(sourceActionId || targetActionId)

  if (sourceActionId) source = sourceActionId
  if (targetActionId) target = targetActionId

  const owner = getStepScopedOwner(edge, nodeById, stepScopedNodeTypes)
  const collapseToParent =
    owner &&
    stepIndex !== null &&
    !actionRouted &&
    behavioralRelations.has(edge.relation) &&
    collapsedBehaviorPairs.has(pairKey(owner.ownerId, owner.peerId))

  if (stepIndex !== null && owner && !collapseToParent) {
    if (owner.ownerSide === 'source') {
      source = `${edge.from}:step:${stepIndex}`
    } else {
      target = `${edge.to}:step:${stepIndex}`
    }
  }

  return { source, target, collapseToParent, actionRouted }
}

function getStepScopedOwner(edge, nodeById, stepScopedNodeTypes) {
  const sourceNode = nodeById.get(edge.from)
  const targetNode = nodeById.get(edge.to)

  if (sourceNode && stepScopedNodeTypes.has(sourceNode.type)) {
    return { ownerId: edge.from, peerId: edge.to, ownerSide: 'source' }
  }

  if (targetNode && stepScopedNodeTypes.has(targetNode.type)) {
    return { ownerId: edge.to, peerId: edge.from, ownerSide: 'target' }
  }

  return null
}

function buildRoutedEdgeData(id, source, target, edge, routed) {
  const data = {
    id,
    source,
    target,
    relation: edge.relation,
    ...edge,
    from: source,
    to: target,
  }

  if (routed.collapseToParent) {
    data.collapsed_to_parent = true
  }

  if (routed.actionRouted) {
    data.routed_to_action = true
  }

  return data
}

function mergeRoutedEdge(existingData, edge, routed) {
  const stepIndex = typeof edge.step_index === 'number' ? edge.step_index : null
  const stepName = typeof edge.step_name === 'string' ? edge.step_name : null
  const actionName = normalizeActionName(edge.action_name)
  const stepIndices = new Set(existingData.collapsed_step_indices || [])
  const stepNames = new Set(existingData.collapsed_step_names || [])
  const actionNames = new Set(existingData.collapsed_action_names || [])

  if (typeof existingData.step_index === 'number') {
    stepIndices.add(existingData.step_index)
  }

  if (typeof existingData.step_name === 'string') {
    stepNames.add(existingData.step_name)
  }

  if (stepIndex !== null) {
    stepIndices.add(stepIndex)
  }

  if (stepName) {
    stepNames.add(stepName)
  }

  if (typeof existingData.action_name === 'string') {
    actionNames.add(existingData.action_name)
  }

  if (actionName) {
    actionNames.add(actionName)
  }

  if (stepIndices.size > 0) {
    existingData.collapsed_step_indices = [...stepIndices].sort((a, b) => a - b)
  }

  if (stepNames.size > 0) {
    existingData.collapsed_step_names = [...stepNames].sort()
  }

  if (actionNames.size > 0) {
    existingData.collapsed_action_names = [...actionNames].sort()
  }

  if (stepIndices.size > 1) {
    delete existingData.step_index
    delete existingData.step_name
  }

  if (routed.collapseToParent) {
    existingData.collapsed_to_parent = true
  }

  if (routed.actionRouted) {
    existingData.routed_to_action = true
  }
}

function resolveResourceActionEndpoint(resourceId, actionName, actionIndex) {
  if (!resourceId || !actionName) return null

  const actionNames = actionIndex.get(resourceId)
  if (!actionNames || !actionNames.has(actionName)) return null

  return buildActionNodeId(resourceId, actionName)
}

function addSetValue(map, key, value) {
  const set = map.get(key) || new Set()
  set.add(value)
  map.set(key, set)
}

function pairKey(ownerId, peerId) {
  return `${ownerId}\u0000${peerId}`
}
