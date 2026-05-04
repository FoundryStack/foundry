import { EDGE_CATALOG, edgeRelationSelector, edgeStaticStyle } from './edge_catalog'
import { getTypeColorToken } from './semantics'

const FONT = 'Segoe UI Symbol, Apple Symbols, Arial Unicode MS, sans-serif'

export const FOUNDRY_LAYOUT_OPTIONS = {
  randomize: false,
  idealEdgeLength: 58,
  nodeRepulsion: 3900,
  edgeElasticity: 0.2,
  padding: 32,
  gravity: 0.35,
  gravityCompound: 1.0,
  nestingFactor: 0.18,
}

export const FOUNDRY_COMPOUND_COMPACTION = {
  enabled: true,
  selector: 'node.domain-cluster, node.transfer-cluster, node.resource-cluster, node.fsm-cluster',
  maxChildren: 12,
  minOccupancy: 0.32,
  spacing: 40,
  padding: 48,
  separateDomains: true,
  domainGap: 52,
  domainLabelBufferX: 132,
  domainLabelBufferY: 72,
  domainIterations: 8,
}

export const STATIC_STYLES = [
  {
    selector: 'node',
    style: {
      'shape': 'round-rectangle',
      'width': 170,
      'height': 64,
      'background-opacity': 0.92,
      'border-width': 1.5,
      'border-style': 'solid',
      'border-opacity': 1,
      'font-size': 11,
      'font-family': FONT,
      'text-valign': 'center',
      'text-halign': 'center',
      'text-margin-x': 0,
      'text-margin-y': 0,
      'text-wrap': 'none',
      'padding': 6,
      'label': 'data(label)',
    },
  },
  {
    selector: 'node[nodeKind="entity"], node[nodeKind="step"], node[nodeKind="action"], node[nodeKind="state"], node[nodeKind="output"], node[nodeKind="cluster"]',
    style: { 'label': '' },
  },
  {
    selector: 'node.compliance-gap, node.gap',
    style: { 'border-width': 1, 'border-style': 'dashed' },
  },
  {
    selector: 'node[nodeKind="cluster"]',
    style: {
      'shape': 'round-rectangle',
      'min-width': 180,
      'min-height': 96,
      'padding': 42,
      'border-style': 'dashed',
      'border-width': 1.5,
      'border-opacity': 0.75,
      'background-opacity': 'data(fillOpacity)',
      'text-valign': 'center',
      'text-halign': 'center',
    },
  },
  {
    selector: 'node.domain-cluster',
    style: {
      'border-style': 'dashed',
      'border-width': 1.5,
      'border-opacity': 0.45,
      'background-opacity': 'data(fillOpacity)',
      'min-width': 240,
      'min-height': 140,
      'padding': 96,
    },
  },
  {
    selector: 'node[nodeKind="step"], node[nodeKind="action"], node[nodeKind="state"]',
    style: {
      'width': 88,
      'height': 40,
      'font-size': 9,
      'font-family': FONT,
      'text-valign': 'center',
      'text-halign': 'center',
      'text-wrap': 'none',
    },
  },
  {
    selector: 'node[nodeKind="action"]',
    style: { 'width': 88, 'height': 40 },
  },
  {
    selector: 'node[nodeKind="output"]',
    style: {
      'width': 76,
      'height': 36,
      'font-size': 8,
      'font-family': FONT,
      'text-valign': 'center',
      'text-halign': 'center',
      'text-wrap': 'none',
    },
  },
  {
    selector: 'node:selected',
    style: { 'border-width': 1.5 },
  },
  {
    selector: 'node.phantom-node',
    style: {
      'border-width': 2,
      'border-style': 'dashed',
      'opacity': 0.5,
      'background-opacity': 0.5,
    },
  },
  {
    selector: 'node[type="external"]',
    style: { 'border-style': 'dashed', 'border-width': 1, 'opacity': 0.7 },
  },
  {
    selector: 'node[type="job"]',
    style: { 'border-style': 'dashed', 'border-width': 1.5 },
  },
  {
    selector: 'node[type="trigger"]',
    style: { 'shape': 'barrel', 'border-style': 'dotted', 'border-width': 1.5 },
  },
  {
    selector: 'node[nodeKind="cluster"][type="transfer"], node[nodeKind="cluster"][type="reactor"]',
    style: { 'border-width': 2 },
  },
  {
    selector: 'edge',
    style: {
      'width': 1.5,
      'target-arrow-shape': 'triangle',
      'curve-style': 'bezier',
      'opacity': 0.8,
    },
  },
  ...EDGE_CATALOG.map(edge => ({
    selector: edgeRelationSelector(edge),
    style: edgeStaticStyle(edge),
  })),
  {
    selector: 'edge:compound',
    style: {
      'source-endpoint': 'outside-to-node',
      'target-endpoint': 'outside-to-node',
    },
  },
  {
    selector: 'edge.compound-structural-edge',
    style: {
      'curve-style': 'segments',
      'segment-weights': 0.5,
      'segment-distances': 28,
      'edge-distances': 'intersection',
      'source-endpoint': '90deg',
      'target-endpoint': '270deg',
    },
  },
  {
    selector: 'edge.compound-structural-edge[relation="referenced_by"]',
    style: {
      'segment-distances': -28,
      'source-endpoint': '270deg',
      'target-endpoint': '90deg',
    },
  },
  {
    selector: '.trace, .trace-gap',
    style: { 'border-width': 1 },
  },
  {
    selector: 'node[nodeKind="step"][has_declared_se="true"]',
    style: { 'border-style': 'solid', 'border-width': 1.5 },
  },
  {
    selector: 'node[nodeKind="step"][has_inferred_se="true"]',
    style: { 'border-style': 'dashed', 'border-width': 1.5 },
  },
]

export function dynamicStyles(c) {
  const kindSelectors = [
    'resource',
    'transfer',
    'reactor',
    'rule',
    'job',
    'liveview',
    'liveresource',
    'blueprint',
    'adapter',
    'trigger',
    'external',
    'agent',
    'output',
    'step',
    'action',
    'state',
  ].map(kind => ({
    selector: `node[type="${kind}"]`,
    style: { 'border-color': c[getTypeColorToken(kind)] || c.t2 },
  }))

  return [
    {
      selector: 'node',
    style: {
      'background-color': c.nodeBg,
      'border-color': c.b1,
      'color': c.tx,
    },
  },
    { selector: 'node.compliance-gap, node.gap', style: { 'border-color': c.yw } },
    { selector: 'node.sensitive', style: { 'border-width': 2, 'border-color': c.rd } },
    {
      selector: 'node[nodeKind="cluster"]',
    style: {
      'background-color': 'data(fillColor)',
      'border-color': c.b1,
    },
  },
    { selector: 'node.domain-cluster', style: { 'background-color': 'data(fillColor)', 'border-color': 'data(typeColor)' } },
    ...kindSelectors,
    { selector: 'node:selected', style: { 'border-color': c.ac } },
    {
      selector: 'node[type="external"]',
      style: { 'background-color': c.s3, 'border-color': c.t3 },
    },
    { selector: 'node[nodeKind="step"], node[nodeKind="action"], node[nodeKind="state"]', style: { 'color': c.tx } },
    { selector: 'node[type="job"]',       style: { 'border-color': c.pu } },
    { selector: 'node[type="trigger"]',   style: { 'border-color': c.ac } },
    {
      selector: 'node[nodeKind="cluster"][type="transfer"]',
      style: { 'border-color': c.gn },
    },
    {
      selector: 'node[nodeKind="cluster"][type="reactor"]',
      style: { 'border-color': c.pu },
    },
    { selector: 'node[nodeKind="step"][has_declared_se="true"]',
      style: { 'border-color': c.gn } },
    { selector: 'node[nodeKind="step"][has_inferred_se="true"]',
      style: { 'border-color': c.rd } },
    {
      selector: 'edge',
      style: { 'line-color': c.t2, 'target-arrow-color': c.t2 },
    },
    ...EDGE_CATALOG.map(edge => {
      const color = c[edge.colorKey] || c.t2
      return {
        selector: edgeRelationSelector(edge),
        style: { 'line-color': color, 'target-arrow-color': color },
      }
    }),
    { selector: '.trace, .trace-gap', style: { 'border-color': c.yw } },
  ]
}

export function buildFoundryStyles(colors) {
  return [...STATIC_STYLES, ...dynamicStyles(colors)]
}
