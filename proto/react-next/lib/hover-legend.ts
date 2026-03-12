/**
 * Builds icon legend entries for node hover cards.
 * Matches the indicators shown on graph nodes (Canvas entityTpl).
 */

import type { ResolvedNode } from './data';
import type { GraphNode } from './types';
import {
  TYPE_ICON_SVG,
  INDICATOR_ICON_SVG,
  INDICATOR_TITLES,
  PSE_ICON_SVG,
  PSE_TITLES,
  TYPE_DESCRIPTIONS,
} from './icon-svg';
import { getParentNodeForHover } from './data';

export type LegendEntry = {
  iconKey: string;
  iconSvg?: string;
  label: string;
  description: string;
};

const INDICATOR_MAP: Record<string, string> = {
  pt: 'paper_trail',
  arch: 'archival',
  sm: 'fsm',
  adrLinked: 'adrLinked',
  policyPresent: 'policyPresent',
};

const INDICATOR_ORDER = [
  'covered',
  'gap',
  'policyPresent',
  'sensitive',
  'pt',
  'arch',
  'runbook',
  'adrLinked',
  'pm',
  'oban',
  'sm',
  'rl',
] as const;

function buildIndicators(n: {
  gap?: boolean;
  sensitive?: boolean;
  pt?: boolean;
  arch?: boolean;
  pm?: boolean;
  sm?: { on?: boolean };
  oban?: string[] | never[];
  rl?: boolean;
  runbook?: string | null;
  cov?: number;
  adrs?: string[] | never[];
  actions?: unknown[];
  dl?: string | null;
}): Record<string, boolean> {
  const covered = (n.cov ?? 0) >= 80 && !n.gap;
  return {
    gap: !!n.gap,
    sensitive: !!n.sensitive,
    pt: !!n.pt,
    arch: !!n.arch,
    pm: !!n.pm,
    sm: !!(n.sm?.on),
    oban: (n.oban?.length ?? 0) > 0,
    rl: !!n.rl,
    runbook: !!n.runbook,
    covered,
    adrLinked: (n.adrs?.length ?? 0) > 0,
    policyPresent: (n.actions?.length ?? 0) > 0,
  };
}

export function getNodeIconLegend(node: ResolvedNode, nodeId: string): LegendEntry[] {
  const entries: LegendEntry[] = [];
  const type = node.type;
  const typeDesc = TYPE_DESCRIPTIONS[type] ?? type;

  // 1. Type icon entry (agent uses ⊕ in Canvas, no SVG here)
  const typeIconSvg = (type as string) === 'agent' ? '' : (TYPE_ICON_SVG[type] ?? TYPE_ICON_SVG.resource);
  entries.push({
    iconKey: 'type',
    iconSvg: typeIconSvg || undefined,
    label: type.charAt(0).toUpperCase() + type.slice(1),
    description: typeDesc,
  });

  // 2. Indicator entries — use parent's indicators for step/state/output
  const parent = getParentNodeForHover(nodeId);
  const indicatorSource: GraphNode | ResolvedNode = parent ?? node;
  const indicators = buildIndicators(indicatorSource);

  const activeIndicators = INDICATOR_ORDER.filter((k) => indicators[k]);
  for (const k of activeIndicators) {
    const iconKey = INDICATOR_MAP[k] ?? k;
    const svg = INDICATOR_ICON_SVG[iconKey];
    const title = INDICATOR_TITLES[iconKey] ?? k;
    if (title) {
      entries.push({
        iconKey,
        iconSvg: svg,
        label: iconKey.replace(/_/g, ' '),
        description: title,
      });
    }
  }

  // 3. PSE entries — when sensitive and parent/node has them
  const pseSource = parent ?? node;
  if (pseSource && 'sensitive' in pseSource && pseSource.sensitive) {
    const pseParts: string[] = [];
    if ('pt' in pseSource && pseSource.pt) pseParts.push('P');
    if ('arch' in pseSource && pseSource.arch) pseParts.push('S');
    if ('dl' in pseSource && (pseSource.dl === 'ash_postgres' || pseSource.dl === 'ecto')) pseParts.push('E');
    const pse = pseParts.join('');
    for (const ch of pse) {
      const icon = PSE_ICON_SVG[ch];
      const title = PSE_TITLES[ch];
      if (icon && title) {
        entries.push({
          iconKey: `pse-${ch}`,
          iconSvg: icon,
          label: ch,
          description: title,
        });
      }
    }
  }

  return entries;
}

/** Relevant invariants from AGENTS.md that apply to this node. */
export function getRelevantInvariants(
  node: ResolvedNode,
  nodeId: string
): string[] {
  const parent = getParentNodeForHover(nodeId);
  const entity = parent ?? node;
  if (!('sensitive' in entity) || !entity.sensitive) return [];

  const inv: string[] = [];
  inv.push('INV-001: Changes require dual approval');
  // INV-011/012 apply to resources only
  if ('type' in entity && entity.type === 'resource') {
    if ('pt' in entity && !entity.pt) inv.push('INV-011: Sensitive resources must use AshPaperTrail');
    if ('arch' in entity && !entity.arch) inv.push('INV-012: Sensitive resources must use AshArchival');
  }
  return inv;
}
