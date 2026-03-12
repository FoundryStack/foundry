/**
 * Change class inference and approval messaging.
 * Extracted from BottomSheet to avoid inline ternaries.
 */

import type { GraphNode } from './types';

export type ChangeClass = 'sensitive' | 'compliance' | 'behavioral' | 'structural';

export function inferChangeClass(node: GraphNode): ChangeClass {
  if (node.sensitive) return 'sensitive';
  if ((node.reqs?.length ?? 0) > 0) return 'compliance';
  return 'behavioral';
}

export function getApprovalMessage(node: GraphNode): string {
  const cls = inferChangeClass(node);
  switch (cls) {
    case 'sensitive':
      return 'Dual approval required';
    case 'compliance':
      return 'Compliance officer';
    case 'behavioral':
      return 'Domain lead';
    case 'structural':
      return 'Any developer';
    default:
      return 'Domain lead';
  }
}
