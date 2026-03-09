/**
 * Builds Cytoscape elements from Foundry graph data.
 * Converts NODES and EDGES to Cytoscape format with optional compound hierarchy.
 */

import type { GraphNode, GraphEdge, EdgeRelation } from './types';
import { NODE_LAYOUT, DOMAIN_ORDER, TYPE_ICON } from './data';

export type CytoscapeNodeData = {
  id: string;
  label: string;
  type: string;
  domain: string;
  nodeKind: 'entity' | 'step' | 'state' | 'output' | 'cluster';
  parent?: string;
  cov?: number;
  gap?: boolean;
  sensitive?: boolean;
  [key: string]: unknown;
};

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

    elements.push({
      group: 'nodes',
      data: {
        id: n.id,
        label: n.name,
        type: n.type,
        domain: n.domain,
        nodeKind: 'entity',
        cov: n.cov,
        gap: n.gap,
        sensitive: n.sensitive,
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
        type: 'cluster',
        domain,
        nodeKind: 'cluster',
      },
      position: pos,
    });

    // Add entity nodes in this domain as children
    // Exclude: player (-> cluster-player), withdraw/deposit/amlscreen (-> cluster-transfer)
    const excludeIds = new Set([
      ...(domain === 'Identity' ? ['player'] : []),
      ...(domain === 'Finance' ? ['withdraw', 'deposit'] : []),
      ...(domain === 'Compliance' ? ['amlscreen'] : []),
    ]);
    const domainNodes = Object.values(nodes).filter((n) => n.domain === domain && !excludeIds.has(n.id));
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
          type: n.type,
          domain: n.domain,
          nodeKind: 'entity',
          parent: clusterId,
          cov: n.cov,
          gap: n.gap,
          sensitive: n.sensitive,
        },
        position: { x: basePos.x - pos.x, y: basePos.y - pos.y },
        ...(classes ? { classes } : {}),
      });
    }
  }

  // Add step nodes for transfers (inside transfer compound)
  const transferIds = ['withdraw', 'deposit', 'amlscreen'];
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
        type: t.type,
        domain: t.domain,
        nodeKind: 'cluster',
        parent: `cluster-${t.domain.toLowerCase()}`,
      },
      position: { x: tPos.x - (domainPositions[t.domain]?.x ?? 0), y: tPos.y - (domainPositions[t.domain]?.y ?? 0) },
    });

    // Step nodes inside transfer
    t.steps.forEach((step, i) => {
      const stepIcon = TYPE_ICON.step ?? '⇄';
      elements.push({
        group: 'nodes',
        data: {
          id: step.id,
          label: `${stepIcon} ${step.name}`,
          type: 'step',
          domain: t.domain,
          nodeKind: 'step',
          parent: clusterTransferId,
          transferId: tid,
        },
        position: { x: i * 100, y: 20 },
      });
    });

    // Output nodes for withdraw
    if (tid === 'withdraw') {
      const outputCommit = 'withdraw-commit';
      const outputKyc = 'withdraw-error-kyc';
      const outputLimits = 'withdraw-error-limits';
      const outputCompensate = 'withdraw-compensate';

      const outIcon = TYPE_ICON.output ?? '⟐';
      [outputCommit, outputKyc, outputLimits, outputCompensate].forEach((oid, i) => {
        const outLabel = oid.includes('commit') ? 'committed' : oid.includes('error') ? 'error' : 'compensated';
        elements.push({
          group: 'nodes',
          data: {
            id: oid,
            label: `${outIcon} ${outLabel}`,
            type: 'output',
            domain: t.domain,
            nodeKind: 'output',
            parent: clusterTransferId,
          },
          position: { x: t.steps!.length * 100 + 50, y: 20 + (i % 2) * 30 },
        });
      });
    }
  }

  // Add FSM state nodes for Player (inside player compound)
  const player = nodes['player'];
  if (player?.sm?.on && player.sm.states.length) {
    const clusterPlayerId = 'cluster-player';
    const pPos = layout['player'] ?? domainPositions['Identity'] ?? { x: 0, y: 0 };

    const playerIcon = TYPE_ICON[player.type] ?? '⬡';
    elements.push({
      group: 'nodes',
      data: {
        id: clusterPlayerId,
        label: `${playerIcon} ${player.name}`,
        type: 'resource',
        domain: player.domain,
        nodeKind: 'cluster',
        parent: 'cluster-identity',
      },
      position: { x: pPos.x - domainPositions['Identity'].x, y: pPos.y - domainPositions['Identity'].y },
    });

    // Add player entity inside cluster-player
    const playerClasses = [player.gap && 'gap', player.sensitive && 'sensitive'].filter(Boolean).join(' ');
    const playerLabelIcon = TYPE_ICON[player.type] ?? '⬡';
    elements.push({
      group: 'nodes',
      data: {
        id: 'player',
        label: `${playerLabelIcon} ${player.name}`,
        type: player.type,
        domain: player.domain,
        nodeKind: 'entity',
        parent: clusterPlayerId,
        cov: player.cov,
        gap: player.gap,
        sensitive: player.sensitive,
      },
      position: { x: 0, y: 0 },
      ...(playerClasses ? { classes: playerClasses } : {}),
    });

    const stateIcon = TYPE_ICON.state ?? '○';
    player.sm.states.forEach((state, i) => {
      elements.push({
        group: 'nodes',
        data: {
          id: state.id,
          label: `${stateIcon} ${state.name}`,
          type: 'state',
          domain: player.domain,
          nodeKind: 'state',
          parent: clusterPlayerId,
          marker: state.marker,
        },
        position: { x: (i % 2) * 80, y: 30 + Math.floor(i / 2) * 50 },
      });
    });
  }

  // Map transfer IDs to cluster IDs for edges (we use clusters, not entity nodes)
  const transferToCluster: Record<string, string> = {
    withdraw: 'cluster-withdraw',
    deposit: 'cluster-deposit',
    amlscreen: 'cluster-amlscreen',
  };

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

    // Last step to commit (for withdraw)
    if (tid === 'withdraw' && t.steps.length) {
      elements.push({
        group: 'edges',
        data: {
          id: `e${edgeIdx++}`,
          source: t.steps[t.steps.length - 1].id,
          target: 'withdraw-commit',
          relation: 'sequence',
        },
      });
    }
  }

  // Add guard edges (Rule -> step)
  const withdraw = nodes['withdraw'];
  if (withdraw?.steps) {
    for (const step of withdraw.steps) {
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

  // Add error and compensation edges for withdraw
  if (withdraw?.steps) {
    const validateStep = withdraw.steps.find((s) => s.guardRules.includes('kyccheck'));
    const limitsStep = withdraw.steps.find((s) => s.guardRules.includes('rgcheck'));
    const debitStep = withdraw.steps.find((s) => s.compensation);

    if (validateStep) {
      elements.push({
        group: 'edges',
        data: {
          id: `e${edgeIdx++}`,
          source: validateStep.id,
          target: 'withdraw-error-kyc',
          relation: 'error',
        },
      });
    }
    if (limitsStep) {
      elements.push({
        group: 'edges',
        data: {
          id: `e${edgeIdx++}`,
          source: limitsStep.id,
          target: 'withdraw-error-limits',
          relation: 'error',
        },
      });
    }
    if (debitStep) {
      elements.push({
        group: 'edges',
        data: {
          id: `e${edgeIdx++}`,
          source: debitStep.id,
          target: 'withdraw-compensate',
          relation: 'compensation',
        },
      });
    }
  }

  // Add FSM transition edges
  if (player?.sm?.on && player.sm.tr.length) {
    const stateId = (name: string) => player.sm.states.find((s) => s.name === name)?.id;
    for (const tr of player.sm.tr) {
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
