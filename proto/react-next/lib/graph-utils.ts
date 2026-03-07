import type { GraphNode } from './types';
import { NODE_W, NODE_H, TYPE_COLOR, TYPE_ABBR } from './data';

/** Returns the SVG path string for a node's outline shape by type. */
export function nodeShapePath(type: GraphNode['type'], x: number, y: number, W = NODE_W, H = NODE_H): string {
  if (type === 'transfer') {
    const sk = 10;
    return `M${x + sk},${y} L${x + W},${y} L${x + W - sk},${y + H} L${x},${y + H} Z`;
  }
  if (type === 'rule') {
    const mx = x + W / 2, r = 6;
    return `M${mx},${y} L${x + W - r},${y + 10} L${x + W - r},${y + H - 10} L${mx},${y + H} L${x + r},${y + H - 10} L${x + r},${y + 10} Z`;
  }
  if (type === 'reactor') {
    const mx = x + W / 2, my = y + H / 2, t = 8;
    return (
      `M${mx},${y} C${mx + t},${y} ${x + W},${my - t} ${x + W},${my} ` +
      `C${x + W},${my + t} ${mx + t},${y + H} ${mx},${y + H} ` +
      `C${mx - t},${y + H} ${x},${my + t} ${x},${my} ` +
      `C${x},${my - t} ${mx - t},${y} ${mx},${y} Z`
    );
  }
  // resource: rounded rect
  const r = 6;
  return (
    `M${x + r},${y} L${x + W - r},${y} Q${x + W},${y} ${x + W},${y + r} ` +
    `L${x + W},${y + H - r} Q${x + W},${y + H} ${x + W - r},${y + H} ` +
    `L${x + r},${y + H} Q${x},${y + H} ${x},${y + H - r} ` +
    `L${x},${y + r} Q${x},${y} ${x + r},${y} Z`
  );
}

/** Escape HTML entities for SVG text content. */
export function escHtml(s: string): string {
  return (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** Coverage color: green ≥80, yellow ≥50, red <50. */
export function covColor(cov: number): string {
  return cov >= 80 ? '#2dd4bf' : cov >= 50 ? '#f59e0b' : '#f87171';
}

/** Coverage RGB for rgba() use. */
export function covRgb(cov: number): string {
  return cov >= 80 ? '45,212,191' : cov >= 50 ? '245,158,11' : '248,113,113';
}

export { TYPE_COLOR, TYPE_ABBR };
