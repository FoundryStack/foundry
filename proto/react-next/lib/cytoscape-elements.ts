/**
 * Builds Cytoscape elements from Foundry graph data.
 * Converts NODES and EDGES to Cytoscape format with optional compound hierarchy.
 */

import type { GraphNode, GraphEdge, EdgeRelation } from './types';
import { NODE_LAYOUT, DOMAIN_ORDER, TYPE_ICON, TYPE_COLOR, DOMAIN_COLOR } from './data';
import { getTransferNodeIds, getCompoundNodeIds, getFsmResourceIds } from './graph-config';

export type NodeIndicators = {
  gap?: boolean;
  sensitive?: boolean;
  pt?: boolean;
  arch?: boolean;
  pm?: boolean;
  sm?: boolean;
  oban?: boolean;
  rl?: boolean;
  runbook?: boolean;
  covered?: boolean;
  adrLinked?: boolean;
  policyPresent?: boolean;
  pse?: string; // "PSE" | "PS·" | "P·E" etc — only when sensitive
};

export type CytoscapeNodeData = {
  id: string;
  label: string;
  name?: string;
  type: string;
  domain: string;
  nodeKind: 'entity' | 'step' | 'state' | 'output' | 'cluster';
  parent?: string;
  cov?: number;
  gap?: boolean;
  sensitive?: boolean;
  desc?: string;
  reqs?: string[];
  typeColor?: string;
  indicators?: NodeIndicators;
  [key: string]: unknown;
};

function buildIndicators(n: {
  gap?: boolean;
  sensitive?: boolean;
  pt?: boolean;
  arch?: boolean;
  pm?: boolean;
  sm?: { on: boolean };
  oban?: string[];
  rl?: boolean;
  runbook?: string | null;
  cov?: number;
  attrs?: unknown[];
  actions?: unknown[];
  adrs?: string[];
  dl?: string | null;
}): NodeIndicators {
  const covered = (n.cov ?? 0) >= 80 && !n.gap;
  const pse = n.sensitive
    ? [n.pt && 'P', n.arch && 'S', (n.dl === 'ash_postgres' || n.dl === 'ecto') && 'E'].filter(Boolean).join('') || undefined
    : undefined;
  return {
    gap: n.gap,
    sensitive: n.sensitive,
    pt: n.pt,
    arch: n.arch,
    pm: n.pm,
    sm: n.sm?.on,
    oban: (n.oban?.length ?? 0) > 0,
    rl: n.rl,
    runbook: !!n.runbook,
    covered,
    adrLinked: (n.adrs?.length ?? 0) > 0,
    policyPresent: (n.actions?.length ?? 0) > 0,
    pse: pse || undefined,
  };
}

export type CytoscapeEdgeData = {
  id: string;
  source: string;
  target: string;
  relation: EdgeRelation;
};

export type CytoscapeElement = {
  group: 'nodes';
  data: CytoscapeNodeData;
  position?: { x: number; y: number };
  classes?: string;
} | {
  group: 'edges';
  data: CytoscapeEdgeData;
  classes?: string;
};

/**
 * Builds flat Cytoscape elements from NODES and EDGES (no compounds).
 * Uses NODE_LAYOUT for positions.
 */
export function buildCytoscapeElementsFlat(
  nodes: Record<string, GraphNode>,
  edges: GraphEdge[],
  layout: Record<string, { x: number; y: number }>
): CytoscapeElement[] {
  const elements: CytoscapeElement[] = [];

  // Add entity nodes
  for (const n of Object.values(nodes)) {
    const pos = layout[n.id];
    if (!pos) continue;

    const icon = TYPE_ICON[n.type] ?? '';
    elements.push({
      group: 'nodes',
      data: {
        id: n.id,
        label: icon ? `${icon} ${n.name}` : n.name,
        name: n.name,
        type: n.type,
        domain: n.domain,
        nodeKind: 'entity',
        cov: n.cov,
        gap: n.gap,
        sensitive: n.sensitive,
        desc: n.desc,
        reqs: n.reqs,
        typeColor: TYPE_COLOR[n.type],
        indicators: buildIndicators(n),
      },
      position: { x: pos.x, y: pos.y },
    });
  }

  // Add edges
  let edgeIdx = 0;
  for (const e of edges) {
    if (layout[e.f] && layout[e.t]) {
      elements.push({
        group: 'edges',
        data: {
          id: `e${edgeIdx++}`,
          source: e.f,
          target: e.t,
          relation: e.r,
        },
      });
    }
  }

  return elements;
}

/**
 * Builds Cytoscape elements with compound hierarchy.
 * Creates domain clusters, Transfer swimlanes, Resource FSM clusters,
 * step nodes, state nodes, and output nodes.
 */
export function buildCytoscapeElements(
  nodes: Record<string, GraphNode>,
  edges: GraphEdge[],
  layout: Record<string, { x: number; y: number }>,
  options?: { useCompounds?: boolean }
): CytoscapeElement[] {
  const useCompounds = options?.useCompounds ?? true;

  if (!useCompounds) {
    return buildCytoscapeElementsFlat(nodes, edges, layout);
  }

  const elements: CytoscapeElement[] = [];
  let edgeIdx = 0;

  // Domain cluster positions (centroids from NODE_LAYOUT)
  const domainPositions: Record<string, { x: number; y: number }> = {
    Identity: { x: 140, y: 180 },
    Finance: { x: 500, y: 200 },
    Compliance: { x: 750, y: 200 },
    Game: { x: 400, y: 440 },
  };

  for (const domain of DOMAIN_ORDER) {
    const clusterId = `cluster-${domain.toLowerCase()}`;
    const pos = domainPositions[domain] ?? { x: 0, y: 0 };

    // Add domain cluster (compound parent)
    elements.push({
      group: 'nodes',
      data: {
        id: clusterId,
        label: domain,
        name: domain,
        type: 'cluster',
        domain,
        nodeKind: 'cluster',
        typeColor: DOMAIN_COLOR[domain] ?? '#9090b0',
      },
      position: pos,
    });

    // Add entity nodes in this domain as children
    // Exclude compound nodes (rendered as cluster children elsewhere)
    const compoundIds = new Set(getCompoundNodeIds(nodes));
    const domainNodes = Object.values(nodes).filter((n) => n.domain === domain && !compoundIds.has(n.id));
    for (let i = 0; i < domainNodes.length; i++) {
      const n = domainNodes[i];
      const basePos = layout[n.id] ?? { x: pos.x + (i % 3) * 120, y: pos.y + Math.floor(i / 3) * 80 };

      const icon = TYPE_ICON[n.type] ?? '';
      const classes = [n.gap && 'gap', n.sensitive && 'sensitive'].filter(Boolean).join(' ');
      elements.push({
        group: 'nodes',
        data: {
          id: n.id,
          label: icon ? `${icon} ${n.name}` : n.name,
          name: n.name,
          type: n.type,
          domain: n.domain,
          nodeKind: 'entity',
          parent: clusterId,
          cov: n.cov,
          gap: n.gap,
          sensitive: n.sensitive,
          desc: n.desc,
          reqs: n.reqs,
          typeColor: TYPE_COLOR[n.type],
          indicators: buildIndicators(n),
        },
        position: { x: basePos.x - pos.x, y: basePos.y - pos.y },
        ...(classes ? { classes } : {}),
      });
    }
  }

  // Add step nodes for transfers (inside transfer compound)
  const transferIds = getTransferNodeIds(nodes);
  for (const tid of transferIds) {
    const t = nodes[tid];
    if (!t?.steps?.length) continue;

    const clusterTransferId = `cluster-${tid}`;
    const tPos = layout[tid] ?? domainPositions[t.domain] ?? { x: 0, y: 0 };

    // Transfer swimlane compound
    const transferIcon = TYPE_ICON[t.type] ?? '⇄';
    elements.push({
      group: 'nodes',
      data: {
        id: clusterTransferId,
        label: `${transferIcon} ${t.name}`,
        name: t.name,
        type: t.type,
        domain: t.domain,
        nodeKind: 'cluster',
        parent: `cluster-${t.domain.toLowerCase()}`,
        desc: t.desc,
        typeColor: TYPE_COLOR[t.type],
        indicators: buildIndicators(t),
      },
      position: { x: tPos.x - (domainPositions[t.domain]?.x ?? 0), y: tPos.y - (domainPositions[t.domain]?.y ?? 0) },
    });

    // Step nodes inside transfer (ADR-017: agent steps use ⊕ icon)
    t.steps.forEach((step, i) => {
      const isAgent = step.kind === 'agent';
      const stepIcon = isAgent ? '⊕' : (TYPE_ICON.step ?? '⇄');
      const stepLabel = isAgent && step.agent_type
        ? `${step.name} · ${step.agent_type}`
        : step.name;
      elements.push({
        group: 'nodes',
        data: {
          id: step.id,
          label: `${stepIcon} ${stepLabel}`,
          name: stepLabel,
          type: isAgent ? 'agent' : 'step',
          domain: t.domain,
          nodeKind: 'step',
          parent: clusterTransferId,
          transferId: tid,
          reqs: step.reqs,
          typeColor: isAgent ? 'var(--pu)' : TYPE_COLOR.step,
          indicators: buildIndicators(t),
        },
        position: { x: i * 100, y: 40 },
      });
    });

    // Output nodes — from transfer.outputs metadata
    const outputs = t.outputs ?? [];
    const outIcon = TYPE_ICON.output ?? '⟐';
    outputs.forEach((out, i) => {
      elements.push({
        group: 'nodes',
        data: {
          id: out.id,
          label: `${outIcon} ${out.label}`,
          name: out.label,
          type: 'output',
          domain: t.domain,
          nodeKind: 'output',
          parent: clusterTransferId,
          typeColor: TYPE_COLOR.output,
          indicators: buildIndicators(t),
        },
        position: { x: t.steps!.length * 100 + 50, y: 40 + (i % 2) * 30 },
      });
    });
  }

  // Add FSM state nodes for resources with state machines
  const fsmResourceIds = getFsmResourceIds(nodes);
  for (const rid of fsmResourceIds) {
    const player = nodes[rid];
    if (!player?.sm?.on || !player.sm.states.length) continue;
    const clusterPlayerId = `cluster-${rid}`;
    const pPos = layout[rid] ?? domainPositions[player.domain] ?? { x: 0, y: 0 };

    const playerIcon = TYPE_ICON[player.type] ?? '⬡';
    elements.push({
      group: 'nodes',
      data: {
        id: clusterPlayerId,
        label: `${playerIcon} ${player.name}`,
        name: player.name,
        type: 'resource',
        domain: player.domain,
        nodeKind: 'cluster',
        parent: `cluster-${player.domain.toLowerCase()}`,
        typeColor: TYPE_COLOR[player.type],
        indicators: buildIndicators(player),
      },
      position: { x: pPos.x - (domainPositions[player.domain]?.x ?? 0), y: pPos.y - (domainPositions[player.domain]?.y ?? 0) },
    });

    // Add player entity inside cluster-player
    const playerClasses = [player.gap && 'gap', player.sensitive && 'sensitive'].filter(Boolean).join(' ');
    const playerLabelIcon = TYPE_ICON[player.type] ?? '⬡';
    elements.push({
      group: 'nodes',
      data: {
        id: rid,
        label: `${playerLabelIcon} ${player.name}`,
        name: player.name,
        type: player.type,
        domain: player.domain,
        nodeKind: 'entity',
        parent: clusterPlayerId,
        cov: player.cov,
        gap: player.gap,
        sensitive: player.sensitive,
        desc: player.desc,
        typeColor: TYPE_COLOR[player.type],
        indicators: buildIndicators(player),
      },
      position: { x: 0, y: 40 },
      ...(playerClasses ? { classes: playerClasses } : {}),
    });

    const stateIcon = TYPE_ICON.state ?? '○';
    player.sm.states.forEach((state, i) => {
      elements.push({
        group: 'nodes',
        data: {
          id: state.id,
          label: `${stateIcon} ${state.name}`,
          name: state.name,
          type: 'state',
          domain: player.domain,
          nodeKind: 'state',
          parent: clusterPlayerId,
          marker: state.marker,
          typeColor: TYPE_COLOR.state,
          indicators: buildIndicators(player),
        },
        position: { x: (i % 2) * 80, y: 50 + Math.floor(i / 2) * 50 },
      });
    });
  }

  // Map transfer/compound IDs to cluster IDs for edges
  const compoundIds = getCompoundNodeIds(nodes);
  const transferToCluster: Record<string, string> = Object.fromEntries(
    compoundIds.map((id) => [id, `cluster-${id}`])
  );

  // Add edges (map transfer refs to cluster refs)
  for (const e of edges) {
    const src = transferToCluster[e.f] ?? e.f;
    const tgt = transferToCluster[e.t] ?? e.t;
    const hasSource = elements.some((el) => el.group === 'nodes' && (el as { data: CytoscapeNodeData }).data.id === src);
    const hasTarget = elements.some((el) => el.group === 'nodes' && (el as { data: CytoscapeNodeData }).data.id === tgt);
    if (hasSource && hasTarget) {
      elements.push({
        group: 'edges',
        data: {
          id: `e${edgeIdx++}`,
          source: src,
          target: tgt,
          relation: e.r,
        },
      });
    }
  }

  // Add sequence edges for transfer steps
  for (const tid of transferIds) {
    const t = nodes[tid];
    if (!t?.steps?.length) continue;

    for (let i = 0; i < t.steps.length - 1; i++) {
      elements.push({
        group: 'edges',
        data: {
          id: `e${edgeIdx++}`,
          source: t.steps[i].id,
          target: t.steps[i + 1].id,
          relation: 'sequence',
        },
      });
    }

    // Edges from steps to outputs (from outputs metadata)
    const outputs = t.outputs ?? [];
    for (const out of outputs) {
      if (out.relation === 'sequence' && out.fromStep === 'last' && t.steps.length) {
        elements.push({
          group: 'edges',
          data: {
            id: `e${edgeIdx++}`,
            source: t.steps[t.steps.length - 1].id,
            target: out.id,
            relation: 'sequence',
          },
        });
      } else if (out.relation === 'error' && out.fromGuard) {
        const step = t.steps.find((s) => s.guardRules.includes(out.fromGuard!));
        if (step) {
          elements.push({
            group: 'edges',
            data: {
              id: `e${edgeIdx++}`,
              source: step.id,
              target: out.id,
              relation: 'error',
            },
          });
        }
      } else if (out.relation === 'compensation' && out.fromCompensation) {
        const step = t.steps.find((s) => s.compensation);
        if (step) {
          elements.push({
            group: 'edges',
            data: {
              id: `e${edgeIdx++}`,
              source: step.id,
              target: out.id,
              relation: 'compensation',
            },
          });
        }
      }
    }
  }

  // Add guard edges (Rule -> step) for all transfers with steps
  for (const tid of transferIds) {
    const t = nodes[tid];
    if (!t?.steps) continue;
    for (const step of t.steps) {
      for (const ruleId of step.guardRules) {
        elements.push({
          group: 'edges',
          data: {
            id: `e${edgeIdx++}`,
            source: ruleId,
            target: step.id,
            relation: 'guard',
          },
        });
      }
    }
  }

  // Add FSM transition edges for all FSM resources
  for (const rid of fsmResourceIds) {
    const fsmNode = nodes[rid];
    if (!fsmNode?.sm?.on || !fsmNode.sm.tr.length) continue;
    const stateId = (name: string) => fsmNode.sm.states.find((s) => s.name === name)?.id;
    for (const tr of fsmNode.sm.tr) {
      const fromId = tr.f === 'any' ? undefined : stateId(tr.f);
      const toId = stateId(tr.t);
      if (fromId && toId) {
        elements.push({
          group: 'edges',
          data: {
            id: `e${edgeIdx++}`,
            source: fromId,
            target: toId,
            relation: 'sequence',
          },
        });
      }
    }
  }

  return elements;
}
