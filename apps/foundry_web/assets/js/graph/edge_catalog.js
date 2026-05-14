// Edge catalog for the full system map.
//
// Keep this grounded in the relation sources that Foundry actually emits:
// - apps/foundry/lib/foundry/context/edge_entry.ex for backend context edges.
// - apps/foundry/lib/foundry/context/graph_builder.ex for source-derived edges.
// - graph/elements.js for UI child edges such as step sequence and FSM eligibility.
export const EDGE_CATALOG = [
  {
    relation: 'sequence',
    label: 'sequence',
    source: 'Reactor/Transfer step order',
    description: 'Execution order between child steps.',
    colorVar: '--fg-edge-sequence',
    colorKey: 'edgeSequence',
    width: 1.4,
    lineStyle: 'solid',
    marker: 'arrow',
  },
  {
    relation: 'triggers',
    label: 'triggers',
    source: 'Boundary trigger or FSM action transition',
    description: 'A trigger/action starts the next flow or state.',
    colorVar: '--fg-edge-trigger',
    colorKey: 'edgeTrigger',
    width: 1.6,
    lineStyle: 'solid',
    marker: 'circle',
    arrowShape: 'circle',
  },
  {
    relation: 'writes',
    label: 'writes',
    source: 'Reactor/Transfer write target',
    description: 'A step creates, updates, or destroys resource data.',
    colorVar: '--fg-edge-write',
    colorKey: 'edgeWrite',
    width: 1.6,
    lineStyle: 'solid',
    marker: 'diamond-filled',
    arrowShape: 'diamond',
  },
  {
    relation: 'reads',
    label: 'reads',
    source: 'Reactor/Transfer read target',
    description: 'A step reads resource data.',
    colorVar: '--fg-edge-read',
    colorKey: 'edgeRead',
    width: 1.3,
    lineStyle: 'solid',
    marker: 'diamond-open',
    arrowShape: 'diamond',
    arrowFill: 'hollow',
  },
  {
    relation: 'guards',
    aliases: ['guard'],
    label: 'guards',
    source: 'Policy/rule checks',
    description: 'A rule or policy check gates access or execution.',
    colorVar: '--fg-edge-guard',
    colorKey: 'edgeGuard',
    width: 1.35,
    lineStyle: 'dotted',
    marker: 'arrow',
  },
  {
    relation: 'eligibleIf',
    label: 'eligible-if',
    source: 'Resource FSM transition',
    description: 'A state makes an action eligible before the action triggers another state.',
    colorVar: '--fg-edge-eligible',
    colorKey: 'edgeEligible',
    width: 1.2,
    lineStyle: 'dashed',
    marker: 'arrow',
  },
  {
    relation: 'async',
    label: 'async',
    source: 'Oban job performs Reactor',
    description: 'Asynchronous job-to-flow execution.',
    colorVar: '--fg-edge-async',
    colorKey: 'edgeAsync',
    width: 1.5,
    lineStyle: 'dashed',
    marker: 'arrow',
  },
  {
    relation: 'enqueues',
    label: 'enqueues',
    source: 'Trigger/job side effect',
    description: 'A boundary event enqueues a job.',
    colorVar: '--fg-edge-enqueue',
    colorKey: 'edgeEnqueue',
    width: 1.5,
    lineStyle: 'dashed',
    marker: 'arrow',
  },
  {
    relation: 'compensation',
    label: 'compensation',
    source: 'Reactor compensation path',
    description: 'Rollback or saga compensation relationship.',
    colorVar: '--fg-edge-compensation',
    colorKey: 'edgeCompensation',
    width: 2.1,
    lineStyle: 'solid',
    marker: 'arrow',
  },
  {
    relation: 'references',
    label: 'references',
    source: 'Ash belongs_to relationship',
    description: 'Structural foreign-key style dependency.',
    colorVar: '--fg-edge-reference',
    colorKey: 'edgeReference',
    width: 1.1,
    lineStyle: 'dashed',
    marker: 'arrow',
    opacity: 0.72,
  },
  {
    relation: 'referenced_by',
    label: 'referenced-by',
    source: 'Ash has_one/has_many relationship',
    description: 'Inverse structural relationship from parent to related resources.',
    colorVar: '--fg-edge-referenced-by',
    colorKey: 'edgeReferencedBy',
    width: 1.1,
    lineStyle: 'dotted',
    marker: 'vee',
    arrowShape: 'vee',
    opacity: 0.76,
  },
  {
    relation: 'configures',
    label: 'configures',
    source: 'Context edge schema',
    description: 'A config module/resource configures a downstream flow.',
    colorVar: '--fg-edge-configure',
    colorKey: 'edgeConfigure',
    width: 1.4,
    lineStyle: 'dashed',
    marker: 'arrow',
  },
  {
    relation: 'authenticates',
    label: 'authenticates',
    source: 'AshAuthentication subject/token resources',
    description: 'Authentication subject connects to token resources.',
    colorVar: '--fg-edge-auth',
    colorKey: 'edgeAuth',
    width: 1.8,
    lineStyle: 'dashed',
    marker: 'arrow',
  },
  {
    relation: 'persists_to',
    label: 'persists-to',
    source: 'External infrastructure derivation',
    description: 'Resource persistence to generated external storage nodes.',
    colorVar: '--fg-edge-persist',
    colorKey: 'edgePersist',
    width: 1,
    lineStyle: 'dotted',
    marker: 'arrow',
  },
  {
    relation: 'queues_via',
    label: 'queues-via',
    source: 'External infrastructure derivation',
    description: 'Job/Reactor queue dependency.',
    colorVar: '--fg-edge-queue',
    colorKey: 'edgeQueue',
    width: 1.15,
    lineStyle: 'dotted',
    marker: 'arrow',
  },
  {
    relation: 'calls_adapter',
    label: 'calls-adapter',
    source: 'Adapter derivation',
    description: 'Adapter module calls an external system.',
    colorVar: '--fg-edge-adapter',
    colorKey: 'edgeAdapter',
    width: 1.5,
    lineStyle: 'dotted',
    marker: 'arrow',
  },
  {
    relation: 'calls_action',
    label: 'calls-action',
    source: 'Page/LiveView action invocation',
    description: 'A page calls an Ash resource action.',
    colorVar: '--fg-pu',
    colorKey: 'pu',
    width: 1.5,
    lineStyle: 'dashed',
    marker: 'arrow',
  },
  {
    relation: 'feature_flagged_by',
    label: 'feature-flagged-by',
    source: 'Feature flag dependency',
    description: 'A page is controlled by a feature flag.',
    colorVar: '--fg-b2',
    colorKey: 'b2',
    width: 1.2,
    lineStyle: 'dotted',
    marker: 'arrow',
  },
]

export function edgeRelationSelector(edge) {
  return [edge.relation, ...(edge.aliases || [])]
    .map(relation => `edge[relation="${relation}"]`)
    .join(', ')
}

export function edgeStaticStyle(edge) {
  const style = {
    'width': edge.width,
    'target-arrow-shape': edge.arrowShape || 'triangle',
  }

  if (edge.lineStyle && edge.lineStyle !== 'solid') {
    style['line-style'] = edge.lineStyle
  }

  if (edge.arrowFill) {
    style['target-arrow-fill'] = edge.arrowFill
  }

  if (edge.opacity) {
    style['opacity'] = edge.opacity
  }

  return style
}

export function edgeLegendDash(edge) {
  if (edge.lineStyle === 'dashed') return '5 4'
  if (edge.lineStyle === 'dotted') return '1.5 3'
  return ''
}
