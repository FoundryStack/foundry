'use client';

import { TYPE_COLOR, getNodeForHover } from '@/lib/data';
import { covColor } from '@/lib/graph-utils';
import { getHoverExtraRows } from '@/lib/hover-renderers';
import type { Lens } from '@/lib/types';

type Props = {
  nodeId: string;
  lens: Lens;
  pos: { x: number; y: number };
};

export default function HoverCard({ nodeId, lens, pos }: Props) {
  const n = getNodeForHover(nodeId);
  if (!n) return null;

  const tc = TYPE_COLOR[n.type];
  const hc = covColor(n.cov);

  const reqPills = n.reqs.map((r) => (
    <span
      key={r}
      style={{
        fontFamily: 'var(--font-mono)', fontSize: 8, padding: '1px 4px', borderRadius: 2, margin: 1,
        background: n.gap ? 'var(--ywb)' : 'var(--gnb)',
        color: n.gap ? 'var(--yw)' : 'var(--gn)',
        border: `1px solid ${n.gap ? 'var(--ywbd)' : 'var(--gnbd)'}`,
        display: 'inline-flex',
      }}
    >
      {r}
    </span>
  ));

  const infraFlags = [
    n.pt && 'paper_trail',
    n.arch && 'archival',
    (n.oban?.length ?? 0) > 0 && `oban:${n.oban![0]}`,
    n.sm?.on && `fsm(${n.sm.states?.length ?? 0})`,
    n.rl && 'rate-limited',
    n.pm && 'migr!',
  ].filter(Boolean) as string[];

  const extraRows = getHoverExtraRows(lens, n);

  return (
    <div
      style={{
        position: 'absolute', left: pos.x, top: pos.y,
        background: 'var(--s2)', border: '1px solid var(--b3)', borderRadius: 8,
        padding: '10px 12px', minWidth: 200, maxWidth: 260,
        boxShadow: '0 8px 32px rgba(0,0,0,.6)', zIndex: 100,
        pointerEvents: 'none', fontSize: 11,
      }}
    >
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
        <span style={{
          fontFamily: 'var(--font-mono)', fontSize: 8, padding: '2px 5px', borderRadius: 3,
          background: tc + '22', color: tc, border: `1px solid ${tc}44`,
        }}>
          {n.type.toUpperCase()}
        </span>
        <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--tx)' }}>{n.name}</span>
        {n.sensitive && <span style={{ fontSize: 9, color: 'var(--rd)' }}>sensitive</span>}
      </div>

      {/* Rows */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        <Row k="domain" v={n.domain} vc="var(--ac2)" />
        {/* Coverage bar */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>coverage</span>
          <div style={{ flex: 1, height: 3, background: 'var(--s5)', borderRadius: 99, overflow: 'hidden' }}>
            <div style={{ width: `${n.cov}%`, height: '100%', background: hc, borderRadius: 99 }} />
          </div>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: hc }}>{n.cov}%</span>
        </div>
        <Row k="compliance" v={n.gap ? 'gap' : 'covered'} vc={n.gap ? 'var(--yw)' : 'var(--gn)'} />

        {extraRows}

        {reqPills.length > 0 && (
          <>
            <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>reqs</span>
              <span style={{ flex: 1 }}>{reqPills}</span>
            </div>
          </>
        )}

        {infraFlags.length > 0 && (
          <>
            <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 3 }}>
              {infraFlags.map((f) => (
                <span key={f} style={{ fontFamily: 'var(--font-mono)', fontSize: 8, padding: '1px 4px', borderRadius: 2, background: 'var(--s3)', color: 'var(--t2)', border: '1px solid var(--b2)' }}>
                  {f}
                </span>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function Row({ k, v, vc }: { k: string; v: string; vc?: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66, flexShrink: 0 }}>{k}</span>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: vc ?? 'var(--tx)' }}>{v}</span>
    </div>
  );
}
