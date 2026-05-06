import {
  computeCoverageScore,
  formatNodeDisplayLabel,
  formatStepKindLabel,
  getComplianceStatus,
  normalizeGraphNodeType,
} from './semantics'

export function normalizeStateName(value) {
  if (value == null) return null
  return String(value).replace(/^:/, '')
}

export function normalizeActionName(value) {
  if (value == null) return null
  return String(value).replace(/^:/, '')
}

export function normalizeActionType(value) {
  if (value == null) return null
  return String(value).replace(/^:/, '')
}

export function buildStateNodeId(nodeId, stateName) {
  return `${nodeId}:state:${stateName}`
}

export function buildActionNodeId(nodeId, actionName) {
  return `${nodeId}:action:${actionName}`
}

export function normalizeNode(raw) {
  const tc = raw.test_coverage || {}
  const sm = raw.state_machine || {}

  const cov = computeCoverageScore(tc)
  const reqs = raw.compliance || []
  const complianceStatus = getComplianceStatus(reqs, tc)
  const type = normalizeGraphNodeType(raw.type)

  const actions = (raw.actions || []).map((action, index) => {
    const normalizedName = normalizeActionName(action.name || `action_${index}`)
    const normalizedType = normalizeActionType(action.type || 'read')

    return {
      ...action,
      name: normalizedName,
      type: normalizedType,
      nodeKind: 'action',
      id: buildActionNodeId(raw.id, normalizedName),
    }
  })

  const states = (sm.states || []).map(name => {
    const normalizedName = normalizeStateName(name)
    return {
      id: buildStateNodeId(raw.id, normalizedName),
      name: normalizedName,
      nodeKind: 'state',
    }
  }).filter(state => state.name)

  const smTransitions = (sm.transitions || []).map((transition, idx) => {
    const from = normalizeStateName(transition.from)
    const to = normalizeStateName(transition.to)
    const action = normalizeActionName(transition.action)

    return {
      ...transition,
      id: `${raw.id}:transition:${idx}`,
      from,
      to,
      action,
    }
  }).filter(transition => transition.from && transition.to)

  const stateByName = new Map(states.map(state => [state.name, state]))
  smTransitions.forEach(transition => {
    if (!stateByName.has(transition.from)) {
      const state = { id: buildStateNodeId(raw.id, transition.from), name: transition.from, nodeKind: 'state' }
      states.push(state)
      stateByName.set(transition.from, state)
    }

    if (!stateByName.has(transition.to)) {
      const state = { id: buildStateNodeId(raw.id, transition.to), name: transition.to, nodeKind: 'state' }
      states.push(state)
      stateByName.set(transition.to, state)
    }
  })

  const steps = (raw.steps || []).map(s => ({
    ...s,
    display_kind: formatStepKindLabel(s.step_kind || s.type || 'step'),
    agent: (raw.agent_steps || []).find(a => a.step_id === s.id),
  }))

  const description = raw.description || (raw.type && raw.domain
    ? `${raw.type} in ${raw.domain}`
    : raw.type || 'No description')

  return {
    ...raw,
    id: raw.id,
    display_label: formatNodeDisplayLabel(raw.id),
    type,
    domain: raw.domain,
    description,
    nodeKind: 'entity',
    cov,
    reqs,
    gap: complianceStatus.hasGap,
    compliance_gap: complianceStatus.hasGap,
    has_compliance_links: complianceStatus.hasLinks,
    compliance_status: complianceStatus.label,
    sensitive: raw.sensitive,
    pt: raw.paper_trail,
    arch: raw.archival,
    dl: raw.data_layer,
    rl: raw.rate_limited,
    sm: states.length > 0 ? { states, transitions: smTransitions } : null,
    actions,
    steps,
    routes: raw.api_routes || [],
    money: raw.money_attributes || [],
    flags: raw.feature_flags || [],
    rules: raw.rules || [],
    runbook: raw.runbook,
    adrs: raw.adrs || [],
    pending_migrations: raw.pending_migrations,
    last_modified: raw.last_modified,
    schedule: raw.schedule || null,
    oban_queues: raw.oban_queues || [],
    performs: raw.performs || null,
  }
}
