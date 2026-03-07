'use client';

import { useStore } from '@/lib/store';
import { NODES, REQ_META, TYPE_COLOR } from '@/lib/data';
import { covColor } from '@/lib/graph-utils';

const BTN_P: React.CSSProperties = {
  display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5,
  padding: '8px 12px', background: 'var(--ac)', border: 'none', borderRadius: 'var(--r)',
  fontFamily: 'var(--font-sans)', fontSize: 12, fontWeight: 500, color: '#fff',
  cursor: 'pointer', width: '100%', transition: '.12s',
};
const BTN_G: React.CSSProperties = {
  display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5,
  padding: '7px 12px', background: 'none', border: '1px solid var(--b3)', borderRadius: 'var(--r)',
  fontFamily: 'var(--font-sans)', fontSize: 12, color: 'var(--t2)',
  cursor: 'pointer', width: '100%', transition: '.12s',
};

const ACTION_BADGE_COLORS: Record<string, { bg: string; color: string; border: string }> = {
  sen: { bg: 'var(--rdb)',  color: 'var(--rd)',  border: 'var(--rdbd)' },
  beh: { bg: 'var(--pub)',  color: 'var(--pu)',  border: 'var(--pubd)' },
  com: { bg: 'var(--ywb)',  color: 'var(--yw)',  border: 'var(--ywbd)' },
  str: { bg: 'var(--blb)',  color: 'var(--bl)',  border: 'var(--blbd)' },
};

function sectionLabel(label: string, count?: number) {
  return (
    <div style={{ fontSize: 9, fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 7, display: 'flex', alignItems: 'center', gap: 5 }}>
      {label}
      {count !== undefined && (
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, background: 'var(--s3)', padding: '0 4px', borderRadius: 2, color: 'var(--t2)' }}>{count}</span>
      )}
    </div>
  );
}

export default function DrawerDetails() {
  const selectedId = useStore((s) => s.selectedId);
  const openBottomSheet = useStore((s) => s.openBottomSheet);
  const showToast = useStore((s) => s.showToast);

  const n = selectedId ? NODES[selectedId] : null;
  if (!n) return null;

  const tc = TYPE_COLOR[n.type];
  const hc = covColor(n.cov);
  const covW = n.cov;

  const infoCells = [
    { k: 'paper_trail', v: n.pt ? '✓ yes' : '— no',    cls: n.pt ? '#2dd4bf' : 'var(--t4)' },
    { k: 'archival',    v: n.arch ? '✓ yes' : '— no',   cls: n.arch ? '#2dd4bf' : 'var(--t4)' },
    { k: 'rate_limited',v: n.rl ? '⚠ yes' : '— no',     cls: n.rl ? 'var(--yw)' : 'var(--t4)' },
    { k: 'auth subject',v: n.auth ? '✓ yes' : '— no',   cls: n.auth ? '#2dd4bf' : 'var(--t4)' },
    { k: 'migrations',  v: n.pm ? '⚠ pending' : '— clear', cls: n.pm ? 'var(--yw)' : 'var(--t4)' },
    { k: 'data_layer',  v: n.dl ?? '—',                  cls: 'var(--bl)' },
  ];

  return (
    <>
      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* Identity */}
        <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', marginBottom: 3 }}>{n.module}</div>
          <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--tx)', letterSpacing: '-.01em' }}>{n.name}</div>
          <div style={{ fontSize: 11, color: 'var(--t2)', lineHeight: 1.65, marginTop: 6 }}>{n.desc}</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 8 }}>
            <Tag color="var(--ac2)" bg="var(--acb)" border="var(--acbd)">{n.domain}</Tag>
            <Tag color="var(--t2)" bg="var(--s3)" border="var(--b3)">{n.type}</Tag>
            {n.sensitive && <Tag color="var(--rd)" bg="var(--rdb)" border="var(--rdbd)">sensitive</Tag>}
            {n.gap
              ? <Tag color="var(--yw)" bg="var(--ywb)" border="var(--ywbd)">compliance gap</Tag>
              : <Tag color="var(--gn)" bg="var(--gnb)" border="var(--gnbd)">covered</Tag>
            }
            {n.auth && <Tag color="var(--t2)" bg="var(--s3)" border="var(--b3)">auth-subject</Tag>}
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, marginTop: 8 }}>
            <MetaPill>{'📅'} {n.mod}</MetaPill>
            {n.oban.length > 0 && <MetaPill>{'⚡'} oban:{n.oban[0]}</MetaPill>}
            {n.sm.on && <MetaPill>{'⟳'} fsm({n.sm.states.length})</MetaPill>}
          </div>
        </div>

        {/* Test Coverage */}
        <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
          {sectionLabel('Test Coverage')}
          <div style={{ background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 6, padding: '9px 11px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 7 }}>
              <span style={{ fontSize: 10, color: 'var(--t2)', width: 52 }}>Overall</span>
              <div style={{ flex: 1, height: 4, background: 'var(--s5)', borderRadius: 99, overflow: 'hidden' }}>
                <div style={{ width: `${covW}%`, height: '100%', borderRadius: 99, background: hc, transition: 'width .4s' }} />
              </div>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, width: 30, textAlign: 'right', color: hc }}>{n.cov}%</span>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 4, marginTop: 2 }}>
              {[['Property', n.tests.p], ['Scenario', n.tests.s], ['E2E', n.tests.e]].map(([l, v]) => (
                <div key={l as string} style={{ background: 'var(--s3)', border: '1px solid var(--b2)', borderRadius: 4, padding: '6px 4px', textAlign: 'center' }}>
                  <div style={{ fontSize: 13, lineHeight: 1 }}>
                    <span style={{ color: v ? 'var(--gn)' : 'var(--rd)' }}>{v ? '✓' : '✗'}</span>
                  </div>
                  <div style={{ fontSize: 9, color: 'var(--t3)', marginTop: 2 }}>{l as string}</div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Attributes */}
        {n.attrs && n.attrs.length > 0 && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('Attributes', n.attrs.length)}
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <tbody>
                {n.attrs.map((a) => (
                  <tr key={a.n} style={{ borderBottom: '1px solid var(--b1)' }}>
                    <td style={{ padding: '4px 0', verticalAlign: 'top' }}>
                      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--tx)', fontWeight: 500 }}>{a.n}</span>
                      {a.pii && <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, padding: '1px 3px', borderRadius: 2, marginLeft: 3, background: 'var(--rdb)', color: 'var(--rd)' }}>PII</span>}
                      {a.mon && <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, padding: '1px 3px', borderRadius: 2, marginLeft: 3, background: 'var(--gnb)', color: 'var(--gn)' }}>$</span>}
                    </td>
                    <td style={{ padding: '4px 0', verticalAlign: 'top' }}>
                      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, background: 'var(--blb)', color: 'var(--bl)', padding: '1px 4px', borderRadius: 2 }}>{a.t}</span>
                    </td>
                    <td style={{ padding: '4px 0', verticalAlign: 'top' }}>
                      <div style={{ fontSize: 10, color: 'var(--t3)', lineHeight: 1.4, marginTop: 1 }}>{a.d}</div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Actions */}
        {n.actions && n.actions.length > 0 && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('Actions', n.actions.length)}
            {n.actions.map((a) => {
              const key = a.c.substring(0, 3);
              const badge = ACTION_BADGE_COLORS[key] ?? ACTION_BADGE_COLORS.str;
              return (
                <div key={a.n} style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '4px 0', borderBottom: '1px solid var(--b1)' }}>
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--tx)', flex: 1 }}>{a.n}</span>
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, padding: '2px 5px', borderRadius: 3, border: `1px solid ${badge.border}`, background: badge.bg, color: badge.color }}>:{a.c}</span>
                </div>
              );
            })}
          </div>
        )}

        {/* Compliance requirements */}
        {n.reqs && n.reqs.length > 0 && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('Compliance Requirements', n.reqs.length)}
            {n.reqs.map((r) => {
              const meta = REQ_META[r] ?? { label: '—' };
              return (
                <div
                  key={r}
                  role="button"
                  tabIndex={0}
                  onClick={() => showToast(`${r}: ${meta.label}`)}
                  onKeyDown={(e) => e.key === 'Enter' && showToast(`${r}: ${meta.label}`)}
                  style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '5px 8px', background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 5, marginBottom: 4, cursor: 'pointer', transition: '.1s' }}
                >
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--ac2)', width: 80, flexShrink: 0 }}>{r}</span>
                  <span style={{ fontSize: 10, color: 'var(--t2)', flex: 1, lineHeight: 1.3 }}>{meta.label}</span>
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: 8, padding: '2px 5px', borderRadius: 3, background: n.gap ? 'var(--ywb)' : 'var(--gnb)', color: n.gap ? 'var(--yw)' : 'var(--gn)' }}>
                    {n.gap ? 'GAP' : 'ok'}
                  </span>
                </div>
              );
            })}
          </div>
        )}

        {/* State machine */}
        {n.sm && n.sm.on && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('State Machine')}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginBottom: 6 }}>
              {n.sm.states.map((s) => (
                <span key={s} style={{ fontFamily: 'var(--font-mono)', fontSize: 9, padding: '2px 6px', borderRadius: 3, background: 'var(--s3)', border: '1px solid var(--b2)', color: 'var(--t2)' }}>{s}</span>
              ))}
            </div>
            {n.sm.tr.map((t) => (
              <div key={`${t.f}-${t.t}`} style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 10, color: 'var(--t2)', padding: '2px 0' }}>
                <span>{t.f}</span>
                <span style={{ color: 'var(--t4)' }}>{'→'}</span>
                <span style={{ color: 'var(--gn)' }}>{t.t}</span>
                <span style={{ color: 'var(--t3)', marginLeft: 'auto', fontFamily: 'var(--font-mono)', fontSize: 9 }}>{t.ev}</span>
              </div>
            ))}
          </div>
        )}

        {/* Infrastructure */}
        <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
          {sectionLabel('Infrastructure')}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 4 }}>
            {infoCells.map(({ k, v, cls }) => (
              <div key={k} style={{ background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 4, padding: '5px 8px', display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 10, color: 'var(--t2)', flex: 1 }}>{k}</span>
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: cls }}>{v}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Telemetry */}
        {n.telem && n.telem.length > 0 && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('Telemetry')}
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 4, padding: '5px 8px', display: 'inline-flex' }}>
              {n.telem.map((p, i) => (
                <span key={i}>
                  {i > 0 && <span style={{ color: 'var(--t4)', margin: '0 2px' }}>.</span>}
                  <span style={{ color: 'var(--ac2)' }}>{p}</span>
                </span>
              ))}
            </span>
          </div>
        )}

        {/* Money */}
        {n.money && n.money.length > 0 && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('Money Attributes')}
            {n.money.map((m) => (
              <div key={m.n} style={{ fontFamily: 'var(--font-mono)', fontSize: 10, padding: '3px 0', display: 'flex', gap: 8, borderBottom: '1px solid var(--b1)', color: 'var(--t2)' }}>
                <span style={{ color: 'var(--gn)', width: 64 }}>{m.n}</span>
                <span style={{ flex: 1 }}>{m.t}</span>
                <span style={{ color: 'var(--t3)' }}>{m.cldr}</span>
              </div>
            ))}
          </div>
        )}

        {/* API Routes */}
        {n.routes && n.routes.length > 0 && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('API Routes')}
            {n.routes.map((r) => (
              <div key={r.r} style={{ fontFamily: 'var(--font-mono)', fontSize: 10, padding: '3px 0', display: 'flex', gap: 8, borderBottom: '1px solid var(--b1)', color: 'var(--t2)' }}>
                <span style={{ color: 'var(--bl)' }}>{r.m}</span>
                <span style={{ flex: 1 }}>{r.r}</span>
                <span style={{ color: r.auth ? 'var(--gn)' : 'var(--rd)' }}>{r.auth ? 'auth' : 'open'}</span>
              </div>
            ))}
          </div>
        )}

        {/* Feature flags */}
        {n.flags && n.flags.length > 0 && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('Feature Flags')}
            {n.flags.map((f) => (
              <div key={f.n} style={{ fontFamily: 'var(--font-mono)', fontSize: 10, padding: '3px 0', display: 'flex', gap: 8, borderBottom: '1px solid var(--b1)', color: 'var(--t2)' }}>
                <span style={{ color: 'var(--yw)', flex: 1 }}>{f.n}</span>
                {f.adr && <span style={{ color: 'var(--ac2)' }}>{f.adr}</span>}
              </div>
            ))}
          </div>
        )}

        {/* ADRs */}
        {n.adrs && n.adrs.length > 0 && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('Linked ADRs')}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
              {n.adrs.map((a) => (
                <span
                  key={a}
                  role="button"
                  tabIndex={0}
                  onClick={() => showToast(`Opening ${a}…`)}
                  onKeyDown={(e) => e.key === 'Enter' && showToast(`Opening ${a}…`)}
                  style={{ fontFamily: 'var(--font-mono)', fontSize: 9, padding: '2px 6px', borderRadius: 3, background: 'var(--acb)', color: 'var(--ac2)', border: '1px solid var(--acbd)', cursor: 'pointer' }}
                >
                  {a}
                </span>
              ))}
            </div>
          </div>
        )}

        {/* Runbook */}
        {n.runbook && (
          <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
            {sectionLabel('Runbook')}
            <div
              role="button"
              tabIndex={0}
              onClick={() => showToast('Opening runbook…')}
              onKeyDown={(e) => e.key === 'Enter' && showToast('Opening runbook…')}
              style={{ fontSize: 11, color: 'var(--bl)', cursor: 'pointer' }}
            >
              {'📖'} {n.runbook}
            </div>
          </div>
        )}
      </div>

      {/* CTA buttons */}
      <div style={{ padding: '10px 14px 14px', borderTop: '1px solid var(--b1)', display: 'flex', flexDirection: 'column', gap: 5, flexShrink: 0 }}>
        {n.gap ? (
          <button style={BTN_P} onClick={() => openBottomSheet(n.id)}>
            &#9889; Generate compliance test
          </button>
        ) : null}
        <button style={BTN_G} onClick={() => openBottomSheet(n.id)}>
          Propose change to {n.name}
        </button>
      </div>
    </>
  );
}

function Tag({ children, color, bg, border }: { children: React.ReactNode; color: string; bg: string; border: string }) {
  return (
    <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, padding: '2px 6px', borderRadius: 3, border: `1px solid ${border}`, background: bg, color }}>{children}</span>
  );
}

function MetaPill({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4, background: 'var(--s2)', border: '1px solid var(--b2)', borderRadius: 4, padding: '3px 8px', fontSize: 10, color: 'var(--t2)' }}>
      {children}
    </div>
  );
}
