/**
 * Node type capabilities — defines which node types support which features.
 * Used for drawer tabs, authorization tab visibility, etc.
 */

import type { GraphNode, NodeType } from './types';

export type NodeCapability = 'authorization' | 'steps' | 'fsm' | 'oban';

const NODE_TYPE_CAPABILITIES: Partial<Record<NodeType, NodeCapability[]>> = {
  resource: ['authorization'],
  transfer: ['steps'],
  reactor: ['steps', 'oban'],
};

export function hasCapability(node: GraphNode, cap: NodeCapability): boolean {
  const caps = NODE_TYPE_CAPABILITIES[node.type];
  if (!caps) return false;
  if (cap === 'oban') return (node.oban?.length ?? 0) > 0;
  return caps.includes(cap);
}

const BASE_TABS = [
  { id: 'details', label: 'Details' },
  { id: 'flow', label: 'Flow' },
  { id: 'shortcuts', label: 'Actions' },
] as const;

const AUTHORIZATION_TAB = { id: 'authorization' as const, label: 'Authorization' };

export type DrawerTabId = 'details' | 'flow' | 'shortcuts' | 'authorization';

export function getDrawerTabsForNode(
  node: GraphNode
): readonly { id: DrawerTabId; label: string }[] {
  if (hasCapability(node, 'authorization')) {
    return [...BASE_TABS, AUTHORIZATION_TAB];
  }
  return BASE_TABS;
}
