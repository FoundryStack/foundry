'use client';

import { TYPE_COLOR, getNodeForHover } from '@/lib/data';
import { covColor } from '@/lib/graph-utils';
import { getHoverExtraRows } from '@/lib/hover-renderers';
import { getNodeIconLegend, getRelevantInvariants } from '@/lib/hover-legend';
import { inferChangeClass, getApprovalMessage } from '@/lib/change-class';
import type { Lens } from '@/lib/types';
import type { GraphNode } from '@/lib/types';
import type { LegendEntry } from '@/lib/hover-legend';

type Props = {
  nodeId: string;
  lens: Lens;
  pos: { x: number; y: number };
};

const ROW_STYLE = { height: 1, background: 'var(--b2)', margin: '3px 0' } as const;
const LEGEND_MAX = 6;

export default function HoverCard({ nodeId, lens, pos }: Props) {
  const n = getNodeForHover(nodeId);
  if (!n) return null;

  const tc = TYPE_COLOR[n.type];
  const hc = covColor(n.cov);
  const legend = getNodeIconLegend(n, nodeId);
  const invariants = getRelevantInvariants(n, nodeId);

  const isEntityNode =
    n.type !== 'step' && n.type !== 'state' && n.type !== 'output' && !nodeId.startsWith('cluster-');
  const graphNode = isEntityNode ? (n as GraphNode) : null;
  const changeClass = graphNode ? inferChangeClass(graphNode) : null;
  const approvalMsg = graphNode ? getApprovalMessage(graphNode) : null;

  const reqPills = n.reqs.map((r) => (
    <span
      key={r}
      style={{
        fontFamily: 'var(--font-mono)', fontSize: 7, padding: '1px 3px', borderRadius: 2, margin: 1,
        background: n.gap ? 'var(--ywb)' : 'var(--gnb)',
        color: n.gap ? 'var(--yw)' : 'var(--gn)',
        border: `1px solid ${n.gap ? 'var(--ywbd)' : 'var(--gnbd)'}`,
        display: 'inline-flex',
      }}
    >
      {r}
    </span>
  ));

  const extraRows = getHoverExtraRows(lens, n);

  const legendShown = legend.slice(0, LEGEND_MAX);
  const legendOmitted = legend.length - LEGEND_MAX;

  return (
    <div
      style={{
        position: 'absolute', left: pos.x, top: pos.y,
        background: 'var(--s2)', border: '1px solid var(--b3)', borderRadius: 6,
        padding: '6px 10px', minWidth: 180, maxWidth: 240,
        boxShadow: '0 8px 32px rgba(0,0,0,.6)', zIndex: 100,
        pointerEvents: 'none', fontSize: 10,
      }}
    >
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 5 }}>
        <span style={{
          fontFamily: 'var(--font-mono)', fontSize: 7, padding: '1px 4px', borderRadius: 2,
          background: tc + '22', color: tc, border: `1px solid ${tc}44`,
        }}>
          {n.type.toUpperCase()}
        </span>
        <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--tx)' }}>{n.name}</span>
        {n.sensitive && <span style={{ fontSize: 8, color: 'var(--rd)' }}>sensitive</span>}
      </div>

      {/* Rows */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        <Row k="domain" v={n.domain} vc="var(--ac2)" />
        {/* Coverage bar */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 9 }}>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, color: 'var(--t3)', width: 58 }}>coverage</span>
          <div style={{ flex: 1, height: 3, background: 'var(--s5)', borderRadius: 99, overflow: 'hidden' }}>
            <div style={{ width: `${n.cov}%`, height: '100%', background: hc, borderRadius: 99 }} />
          </div>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, color: hc }}>{n.cov}%</span>
        </div>
        <Row k="compliance" v={n.gap ? 'gap' : 'covered'} vc={n.gap ? 'var(--yw)' : 'var(--gn)'} />

        {extraRows}

        {/* Icon legend */}
        {legend.length > 0 && (
          <>
            <div style={ROW_STYLE} />
            <div style={{ fontSize: 7, fontWeight: 600, letterSpacing: '.08em', textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 2 }}>
              Icons
            </div>
            {legendShown.map((entry) => (
              <LegendRow key={entry.iconKey} entry={entry} typeColor={tc} />
            ))}
            {legendOmitted > 0 && (
              <div style={{ fontSize: 7, color: 'var(--t3)', marginTop: 1 }}>+{legendOmitted} more</div>
            )}
          </>
        )}

        {/* Change class & approval (entity nodes only) */}
        {isEntityNode && changeClass && approvalMsg && (
          <>
            <div style={ROW_STYLE} />
            <Row k="change class" v={`:${changeClass}`} vc="var(--pu)" />
            <Row k="approval" v={approvalMsg} vc="var(--t2)" />
          </>
        )}

        {/* Relevant invariants */}
        {invariants.length > 0 && (
          <>
            <div style={ROW_STYLE} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
              <div style={{ fontSize: 7, fontWeight: 600, letterSpacing: '.08em', textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 1 }}>
                Invariants
              </div>
              {invariants.map((inv) => (
                <div key={inv} style={{ fontSize: 8, color: 'var(--yw)', lineHeight: 1.3 }}>
                  {inv}
                </div>
              ))}
            </div>
          </>
        )}

        {reqPills.length > 0 && (
          <>
            <div style={ROW_STYLE} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 9 }}>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, color: 'var(--t3)', width: 58 }}>reqs</span>
              <span style={{ flex: 1 }}>{reqPills}</span>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function Row({ k, v, vc }: { k: string; v: string; vc?: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 9 }}>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, color: 'var(--t3)', width: 58, flexShrink: 0 }}>{k}</span>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, color: vc ?? 'var(--tx)' }}>{v}</span>
    </div>
  );
}

function LegendRow({ entry, typeColor }: { entry: LegendEntry; typeColor: string }) {
  const iconColor = entry.iconKey === 'type' ? typeColor : 'var(--t2)';
  const iconStyle = {
    flexShrink: 0, width: 14, height: 14, display: 'flex' as const, alignItems: 'center', justifyContent: 'center',
    color: iconColor,
  };
  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 4, fontSize: 8, marginBottom: 1, lineHeight: 1.25 }}>
      {entry.iconSvg ? (
        <span style={iconStyle} dangerouslySetInnerHTML={{ __html: entry.iconSvg }} />
      ) : (
        <span style={iconStyle}>{entry.label.charAt(0)}</span>
      )}
      <div style={{ flex: 1, minWidth: 0 }}>
        <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--t2)', fontWeight: 500 }}>{entry.label}</span>
        <span style={{ color: 'var(--t3)', marginLeft: 3 }}>— {entry.description}</span>
      </div>
    </div>
  );
}
