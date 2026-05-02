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

  const cov = (tc.property_tests ? 33 : 0) + (tc.scenario_tests ? 33 : 0) + (tc.e2e_tests ? 34 : 0)
  const reqs = raw.compliance || []
  const complianceGap = reqs.length > 0 && !tc.e2e_tests
  const type = raw.type === 'provider' ? 'adapter' : raw.type

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
    agent: (raw.agent_steps || []).find(a => a.step_id === s.id),
  }))

  const description = raw.description || (raw.type && raw.domain
    ? `${raw.type} in ${raw.domain}`
    : raw.type || 'No description')

  return {
    id: raw.id,
    type,
    domain: raw.domain,
    description,
    nodeKind: 'entity',
    cov,
    reqs,
    gap: complianceGap,
    compliance_gap: complianceGap,
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
    runbook: raw.runbook,
    adrs: raw.adrs || [],
    pending_migrations: raw.pending_migrations,
    last_modified: raw.last_modified,
    schedule: raw.schedule || null,
    oban_queues: raw.oban_queues || [],
    performs: raw.performs || null,
    ...raw,
  }
}
