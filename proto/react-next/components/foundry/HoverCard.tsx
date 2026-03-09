'use client';

import { NODES, EDGES, TYPE_COLOR, getNodeForHover, getPrimaryNodeId } from '@/lib/data';
import { covColor } from '@/lib/graph-utils';
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
    n.oban.length && `oban:${n.oban[0]}`,
    n.sm.on && `fsm(${n.sm.states.length})`,
    n.rl && 'rate-limited',
    n.pm && 'migr!',
  ].filter(Boolean) as string[];

  // Lens-specific extra rows
  let extraRows: React.ReactNode = null;

  if (lens === 'sen') {
    const pii = n.attrs.filter((a) => a.pii || a.sen);
    const mon = n.money && n.money.length;
    extraRows = (
      <>
        <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
        {n.attrs.length > 0 && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>PII fields</span>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--rd)' }}>{pii.length}/{n.attrs.length}</span>
          </div>
        )}
        {pii.map((a) => (
          <div key={a.n} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66, paddingLeft: 8 }}>{a.n}</span>
            <span style={{ fontSize: 8, color: 'var(--rd)' }}>PII</span>
          </div>
        ))}
        {mon ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>monetary</span>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--yw)' }}>{n.money.length} field{n.money.length !== 1 ? 's' : ''}</span>
          </div>
        ) : null}
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>paper_trail</span>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: n.pt ? 'var(--gn)' : 'var(--yw)' }}>{n.pt ? '✓ yes' : '✗ no'}</span>
        </div>
      </>
    );
  } else if (lens === 'hlth') {
    const mk = (v: boolean, l: string) => (
      <div key={l} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>{l}</span>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: v ? 'var(--gn)' : 'var(--yw)' }}>{v ? '✓' : '✗'}</span>
      </div>
    );
    extraRows = (
      <>
        <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
        {mk(n.tests.p, 'property')}
        {mk(n.tests.s, 'scenario')}
        {mk(n.tests.e, 'e2e')}
      </>
    );
  } else if (lens === 'erd' && n.attrs.length) {
    extraRows = (
      <>
        <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
        {n.attrs.slice(0, 5).map((a) => (
          <div key={a.n} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>{a.n}</span>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--pu)' }}>{a.t}</span>
            {a.pii && <span style={{ fontSize: 7, color: 'var(--rd)', marginLeft: 2 }}>PII</span>}
            {a.mon && <span style={{ fontSize: 7, color: 'var(--yw)', marginLeft: 2 }}>$</span>}
          </div>
        ))}
        {n.attrs.length > 5 && <div style={{ fontSize: 9, color: 'var(--t3)', padding: '2px 0' }}>+{n.attrs.length - 5} more…</div>}
      </>
    );
  } else if (lens === 'imp') {
    const primaryId = getPrimaryNodeId(n.id) ?? n.id;
    const out = EDGES.filter((e) => e.f === primaryId).map((e) => getNodeForHover(e.t)?.name ?? NODES[e.t]?.name ?? e.t);
    const inp = EDGES.filter((e) => e.t === primaryId).map((e) => getNodeForHover(e.f)?.name ?? NODES[e.f]?.name ?? e.f);
    if (out.length || inp.length) {
      extraRows = (
        <>
          <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
          {inp.length > 0 && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>receives from</span>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--bl)', flex: 1, textAlign: 'right' }}>{inp.join(', ')}</span>
            </div>
          )}
          {out.length > 0 && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>sends to</span>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--gn)', flex: 1, textAlign: 'right' }}>{out.join(', ')}</span>
            </div>
          )}
        </>
      );
    }
  } else if (n.type === 'resource' && n.attrs.length) {
    extraRows = (
      <>
        <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
        {n.attrs.slice(0, 3).map((a) => (
          <div key={a.n} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>{a.n}</span>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--bl)' }}>{a.t}</span>
            {a.sen && <span style={{ fontSize: 7, color: 'var(--rd)', marginLeft: 4 }}>PII</span>}
          </div>
        ))}
      </>
    );
  } else if (n.type === 'transfer' || n.type === 'reactor') {
    extraRows = (
      <>
        <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>steps</span>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--ac2)' }}>{n.actions.length} actions</span>
        </div>
      </>
    );
  } else if (n.type === 'rule') {
    extraRows = (
      <>
        <div style={{ height: 1, background: 'var(--b2)', margin: '5px 0' }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>enforces</span>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--yw)' }}>{n.reqs.length} req{n.reqs.length !== 1 ? 's' : ''}</span>
        </div>
      </>
    );
  }

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
