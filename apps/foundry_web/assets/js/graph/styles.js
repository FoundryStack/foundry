import { EDGE_CATALOG, edgeRelationSelector, edgeStaticStyle } from './edge_catalog.js'
import { withAlpha } from './colors.js'
import { getTypeColorToken } from './semantics.js'

const FONT = 'Segoe UI Symbol, Apple Symbols, Arial Unicode MS, sans-serif'

export const FOUNDRY_LAYOUT_OPTIONS = {
  randomize: false,
  quality: 'proof',
  idealEdgeLength: 80,
  nodeRepulsion: 12000,
  edgeElasticity: 0.45,
  padding: 56,
  gravity: 0.14,
  gravityCompound: 1.0,
  gravityRangeCompound: 1.5,
  nestingFactor: 0.55,
  tilingPaddingHorizontal: 32,
  tilingPaddingVertical: 32,
}

export const FOUNDRY_COMPOUND_COMPACTION = {
  enabled: true,
  selector: 'node.domain-cluster, node.transfer-cluster, node.resource-cluster, node.fsm-cluster',
  maxChildren: 20,
  minOccupancy: 0.42,
  spacing: 56,
  padding: 72,
  separateDomains: true,
  domainGap: 64,
  domainLabelBufferX: 132,
  domainLabelBufferY: 104,
  domainIterations: 12,
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
      'overlay-opacity': 0,
      'min-zoomed-font-size': 8,
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
      'padding': 58,
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
      'padding': 144,
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
    style: {
      'border-width': 2,
      'background-opacity': 0.8,
    },
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
    selector: 'node.coverage-uncovered',
    style: {
      'border-width': 2.5,
      'border-style': 'dashed',
    },
  },
  {
    selector: 'node.scenario-failing',
    style: {
      'border-width': 2.5,
      'border-style': 'solid',
    },
  },
  {
    selector: 'node.scenario-untraced',
    style: {
      'border-width': 2,
      'border-style': 'dashed',
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
      'overlay-opacity': 0,
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
    'page',
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
    {
      selector: 'node.coverage-uncovered',
      style: {
        'border-color': c.yw,
        'background-blacken': 0.08,
      },
    },
    {
      selector: 'node.scenario-failing',
      style: {
        'border-color': c.rd,
        'background-blacken': 0.12,
      },
    },
    {
      selector: 'node.scenario-untraced',
      style: {
        'border-color': c.gy,
        'background-blacken': 0.06,
      },
    },
    { selector: 'node.sensitive', style: { 'border-width': 2, 'border-color': c.rd } },
    {
      selector: 'node[nodeKind="cluster"][fillColor]',
      style: {
        'background-color': 'data(fillColor)',
        'border-color': c.b1,
      },
    },
    {
      selector: 'node.domain-cluster[typeColor][fillColor]',
      style: { 'background-color': 'data(fillColor)', 'border-color': 'data(typeColor)' },
    },
    ...kindSelectors,
    {
      selector: 'node:selected[typeColor]',
      style: {
        'border-color': 'data(typeColor)',
        'background-color': 'data(typeColor)',
        'background-opacity': 0.5,
      },
    },
    {
      selector: 'node[type="external"]',
      style: {
        'background-color': c.nodeBg,
        'border-color': c.pk,
        'color': c.tx,
      },
    },
    { selector: 'node[nodeKind="step"], node[nodeKind="action"], node[nodeKind="state"]', style: { 'color': c.tx } },
    { selector: 'node[nodeKind="step"][fillColor]', style: { 'background-color': 'data(fillColor)', 'background-opacity': 1 } },
    { selector: 'node[type="job"]',       style: { 'border-color': c.pu } },
    { selector: 'node[type="trigger"]',   style: { 'border-color': c.ac } },
    {
      selector: 'node[nodeKind="cluster"][type="transfer"]',
      style: { 'border-color': c.gn },
    },
    {
      selector: 'node[nodeKind="cluster"][type="reactor"]',
      style: {
        'border-color': c.sidebarPu,
        'background-color': withAlpha(c.sidebarPu, 0.14),
      },
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
