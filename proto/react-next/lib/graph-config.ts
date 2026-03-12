/**
 * Graph structure helpers — derive compound nodes, transfers, FSM resources,
 * and output parent resolution from node data. No hardcoded node IDs.
 */

import type { GraphNode } from './types';

/** Nodes that are rendered as compounds (have steps or FSM). */
export function getCompoundNodeIds(nodes: Record<string, GraphNode>): string[] {
  return Object.values(nodes).filter(
    (n) => (n.steps?.length ?? 0) > 0 || (n.sm?.on && (n.sm.states?.length ?? 0) > 0)
  ).map((n) => n.id);
}

/** Transfers/reactors with steps (for swimlanes). */
export function getTransferNodeIds(nodes: Record<string, GraphNode>): string[] {
  return Object.values(nodes).filter(
    (n) => (n.steps?.length ?? 0) > 0
  ).map((n) => n.id);
}

/** Resources with FSM (for state clusters). */
export function getFsmResourceIds(nodes: Record<string, GraphNode>): string[] {
  return Object.values(nodes).filter(
    (n) => n.sm?.on && (n.sm.states?.length ?? 0) > 0
  ).map((n) => n.id);
}

/** Resolve output node parent: "withdraw-commit" -> "withdraw". */
export function getOutputParentId(
  nodeId: string,
  nodes: Record<string, GraphNode>
): string | null {
  const transferIds = getTransferNodeIds(nodes);
  for (const tid of transferIds) {
    if (nodeId.startsWith(`${tid}-`)) return tid;
  }
  return null;
}

/** Check if nodeId is a compound (cluster) in the graph. */
export function isCompoundNode(nodeId: string, nodes: Record<string, GraphNode>): boolean {
  return getCompoundNodeIds(nodes).includes(nodeId);
}
