import type { NodeType, EdgeRelation, GraphNode } from './types';
import { DOMAIN_COLOR, TYPE_ICON, NODE_W, NODE_H } from './data';

// ─── Coverage color bands (per spec section 5) ────────────────────────────────

export function covColor(c: number): string {
  if (c >= 80) return '#34d399'; // green
  if (c >= 50) return '#fbbf24'; // amber
  return '#f87171';              // red
}

export function covRgb(c: number): string {
  if (c >= 80) return '52,211,153';
  if (c >= 50) return '251,191,36';
  return '248,113,113';
}

export function covBand(c: number): 'green' | 'amber' | 'red' {
  if (c >= 80) return 'green';
  if (c >= 50) return 'amber';
  return 'red';
}

// ─── Node shape path (all rounded rectangles per spec section 3) ──────────────

export function nodeShapePath(x: number, y: number, w = NODE_W, h = NODE_H, r = 6): string {
  return `M${x + r},${y} h${w - 2 * r} a${r},${r} 0 0 1 ${r},${r} v${h - 2 * r} a${r},${r} 0 0 1 -${r},${r} h-${w - 2 * r} a${r},${r} 0 0 1 -${r},-${r} v-${h - 2 * r} a${r},${r} 0 0 1 ${r},-${r} z`;
}

// ─── Domain left border stripe (per spec section 7) ───────────────────────────

export function domainStripe(domain: string): string {
  return DOMAIN_COLOR[domain] ?? '#6b7280';
}

// ─── Type icon lookup (per spec section 3) ────────────────────────────────────

export function typeIcon(t: NodeType): string {
  return TYPE_ICON[t] ?? '?';
}

// ─── FSM state marker symbols (per spec section 3) ────────────────────────────

export function fsmMarker(marker: 'normal' | 'active' | 'trap'): string {
  if (marker === 'active') return '•';
  if (marker === 'trap') return '⊗';
  return '◦';
}

// ─── Border style for compliance posture (per spec section 6) ─────────────────

export function borderStyle(n: GraphNode): { width: number; dash: string; stroke: string } {
  const isSensitive = n.sensitive;
  const isGap = n.gap;
  const isAuth = n.auth;

  if (isAuth) {
    // Double border — auth boundary
    return { width: 3, dash: '', stroke: '#e8e8f0' };
  }
  if (isSensitive && isGap) {
    // Sensitive + compliance gap — critical
    return { width: 2, dash: '5,3', stroke: '#f87171' };
  }
  if (isSensitive) {
    // Sensitive resource (requires dual approval)
    return { width: 2, dash: '', stroke: '#f87171' };
  }
  if (isGap) {
    // Compliance gap — dashed
    return { width: 2, dash: '5,3', stroke: '#fbbf24' };
  }
  // Normal — all requirements covered
  return { width: 1, dash: '', stroke: 'rgba(70,70,100,.6)' };
}

// ─── Edge style mapping (per spec section 8) ──────────────────────────────────

export type EdgeStyleDef = {
  stroke: string;
  sw: number;
  dash: string;
  marker: string;
};

export function edgeStyle(r: EdgeRelation): EdgeStyleDef {
  switch (r) {
    case 'sequence':
      return { stroke: '#9090b0', sw: 1.5, dash: '', marker: 'arrow' };
    case 'async':
      return { stroke: '#a78bfa', sw: 1.5, dash: '4,4', marker: 'arrow' };
    case 'guard':
      return { stroke: '#fbbf24', sw: 1.2, dash: '2,2', marker: 'arrow' };
    case 'eligibleIf':
      return { stroke: '#fbbf24', sw: 1.2, dash: '4,2,1,2', marker: 'arrow' };
    case 'compensation':
      return { stroke: '#f59e0b', sw: 2, dash: '', marker: 'arrow' };
    case 'error':
      return { stroke: '#ef4444', sw: 1.5, dash: '6,3', marker: 'arrow' };
    case 'reads':
      return { stroke: '#60a5fa', sw: 1.2, dash: '', marker: 'diamond-open' };
    case 'writes':
      return { stroke: '#34d399', sw: 1.5, dash: '', marker: 'diamond-filled' };
    case 'triggers':
      return { stroke: '#7b6ef6', sw: 1.5, dash: '', marker: 'circle' };
    case 'calls':
      return { stroke: 'rgba(70,70,100,.5)', sw: 1, dash: '', marker: 'arrow' };
    case 'enforces':
      return { stroke: '#fbbf24', sw: 1.2, dash: '3,3', marker: 'arrow' };
    case 'references':
      return { stroke: 'rgba(100,100,130,.4)', sw: 1, dash: '5,5', marker: 'arrow' };
    default:
      return { stroke: 'rgba(70,70,100,.5)', sw: 1, dash: '', marker: 'arrow' };
  }
}

// ─── Status indicator helpers ─────────────────────────────────────────────────

export function statusColor(present: boolean, color: string, absent = 'rgba(60,60,80,.5)'): string {
  return present ? color : absent;
}

// ─── HTML escape ──────────────────────────────────────────────────────────────

export function escHtml(s: string): string {
  return (s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ─── Calculate domain coverage (per spec section 14) ──────────────────────────

export function domainCoverage(nodes: GraphNode[]): {
  total: number;
  t: number | null;  // transfer
  r: number | null;  // rule
  c: number | null;  // compliance E2E
  u: number | null;  // UI / LiveResource
} {
  const transfers = nodes.filter(n => n.type === 'transfer' || n.type === 'reactor');
  const rules = nodes.filter(n => n.type === 'rule');
  const uis = nodes.filter(n => n.type === 'liveresource');
  const compliance = nodes.filter(n => n.reqs.length > 0);

  const avg = (arr: GraphNode[]) => arr.length ? Math.round(arr.reduce((a, n) => a + n.cov, 0) / arr.length) : null;

  const t = avg(transfers);
  const r = avg(rules);
  const c = avg(compliance);
  const u = avg(uis);

  // Weighted total
  const weights = [t, r, c, u].filter(v => v !== null) as number[];
  const total = weights.length ? Math.round(weights.reduce((a, v) => a + v, 0) / weights.length) : 0;

  return { total, t, r, c, u };
}

// ─── Bezier curve path for edges ──────────────────────────────────────────────

export function edgePath(x1: number, y1: number, x2: number, y2: number): string {
  const mx = (x1 + x2) / 2;
  return `M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`;
}

// ─── Cytoscape stylesheet (per spec section 8) ─────────────────────────────────

export type CytoscapeStylesheet = Array<
  | { selector: string; style: Record<string, unknown> }
  | { selector: string; css: Record<string, unknown> }
>;

export function toCytoscapeStylesheet(domainColors: Record<string, string>): CytoscapeStylesheet {
  return [
    // Base node (font supports Unicode icons; label centered to avoid broken positioning)
    {
      selector: 'node',
      style: {
        'shape': 'round-rectangle',
        'width': 140,
        'height': 56,
        'background-color': 'rgba(30,30,45,.95)',
        'border-width': 3,
        'border-color': 'rgba(70,70,100,.6)',
        'border-style': 'solid',
        'border-opacity': 1,
        'color': '#c8c8e0',
        'font-size': 11,
        'font-family': 'Segoe UI Symbol, Apple Symbols, Arial Unicode MS, sans-serif',
        'text-valign': 'center',
        'text-halign': 'center',
        'text-margin-x': 0,
        'text-margin-y': 0,
        'text-wrap': 'none',
        'padding': 6,
        'label': 'data(label)',
      },
    },
    // Hide native label for nodes that use HTML overlays (cytoscape-node-html-label)
    {
      selector: 'node[nodeKind="entity"], node[nodeKind="step"], node[nodeKind="state"], node[nodeKind="output"], node[nodeKind="cluster"]',
      style: { 'label': '' },
    },
    // Domain stripe via border-color (3px colored border; Cytoscape has no per-side border)
    {
      selector: 'node[domain="Identity"]',
      style: { 'border-color': domainColors.Identity ?? '#34d399' },
    },
    {
      selector: 'node[domain="Finance"]',
      style: { 'border-color': domainColors.Finance ?? '#60a5fa' },
    },
    {
      selector: 'node[domain="Compliance"]',
      style: { 'border-color': domainColors.Compliance ?? '#fbbf24' },
    },
    {
      selector: 'node[domain="Game"]',
      style: { 'border-color': domainColors.Game ?? '#c084fc' },
    },
    // Gap (compliance) - use .gap class
    {
      selector: 'node.gap',
      style: { 'border-width': 2, 'border-style': 'dashed', 'border-color': '#fbbf24' },
    },
    // Sensitive - use .sensitive class
    {
      selector: 'node.sensitive',
      style: { 'border-width': 2, 'border-color': '#f87171' },
    },
    // Cluster/compound (label hidden; HTML overlay used)
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
        'font-family': 'Segoe UI Symbol, Apple Symbols, Arial Unicode MS, sans-serif',
        'text-valign': 'center',
        'text-halign': 'center',
      },
    },
    // Step/state nodes (smaller, centered labels)
    {
      selector: 'node[nodeKind="step"], node[nodeKind="state"]',
      style: {
        width: 80,
        height: 36,
        'font-size': 9,
        'font-family': 'Segoe UI Symbol, Apple Symbols, Arial Unicode MS, sans-serif',
        'text-valign': 'center',
        'text-halign': 'center',
        'text-wrap': 'none',
      },
    },
    {
      selector: 'node[nodeKind="output"]',
      style: {
        width: 70,
        height: 32,
        'font-size': 8,
        'font-family': 'Segoe UI Symbol, Apple Symbols, Arial Unicode MS, sans-serif',
        'text-valign': 'center',
        'text-halign': 'center',
        'text-wrap': 'none',
      },
    },
    // Selection
    {
      selector: 'node:selected',
      style: { 'border-width': 2.5, 'border-color': '#9d93ff' },
    },
    {
      selector: '.trace',
      style: { 'border-width': 2, 'border-color': '#fbbf24' },
    },
    {
      selector: '.trace-gap',
      style: { 'border-width': 2, 'border-color': '#f59e0b' },
    },
    // Edges by relation
    {
      selector: 'edge',
      style: {
        'width': 1.5,
        'line-color': '#9090b0',
        'target-arrow-color': '#9090b0',
        'target-arrow-shape': 'triangle',
        'curve-style': 'bezier',
        'opacity': 0.8,
      },
    },
    {
      selector: 'edge[relation="sequence"]',
      style: { 'line-color': '#9090b0', 'target-arrow-shape': 'triangle' },
    },
    {
      selector: 'edge[relation="async"]',
      style: { 'line-style': 'dashed', 'line-color': '#a78bfa', 'target-arrow-color': '#a78bfa' },
    },
    {
      selector: 'edge[relation="guard"], edge[relation="eligibleIf"]',
      style: { 'line-style': 'dotted', 'line-color': '#fbbf24', 'target-arrow-color': '#fbbf24', width: 1.2 },
    },
    {
      selector: 'edge[relation="compensation"]',
      style: { width: 2, 'line-color': '#f59e0b', 'target-arrow-color': '#f59e0b' },
    },
    {
      selector: 'edge[relation="error"]',
      style: { 'line-style': 'dashed', 'line-color': '#ef4444', 'target-arrow-color': '#ef4444' },
    },
    {
      selector: 'edge[relation="reads"]',
      style: { 'line-color': '#60a5fa', 'target-arrow-shape': 'diamond', 'target-arrow-fill': 'hollow' },
    },
    {
      selector: 'edge[relation="writes"]',
      style: { 'line-color': '#34d399', 'target-arrow-shape': 'diamond', 'target-arrow-fill': 'filled' },
    },
    {
      selector: 'edge[relation="triggers"]',
      style: { 'line-color': '#7b6ef6', 'target-arrow-shape': 'circle', 'target-arrow-fill': 'filled' },
    },
  ];
}
