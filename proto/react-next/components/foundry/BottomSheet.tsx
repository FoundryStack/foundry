'use client';

import { useStore } from '@/lib/store';
import { NODES, SCENARIOS } from '@/lib/data';

const BTN_P: React.CSSProperties = {
  padding: '8px 18px', background: 'var(--ac)', border: 'none', borderRadius: 'var(--r)',
  fontFamily: 'var(--font-sans)', fontSize: 12, fontWeight: 500, color: '#fff',
  cursor: 'pointer', transition: '.12s',
};
const BTN_G: React.CSSProperties = {
  padding: '7px 14px', background: 'none', border: '1px solid var(--b3)', borderRadius: 'var(--r)',
  fontFamily: 'var(--font-sans)', fontSize: 12, color: 'var(--t2)',
  cursor: 'pointer', transition: '.12s',
};

const DIFF_LINES = [
  { t: '+', v: 'defmodule MyApp.Finance.WithdrawalTransfer do', c: 'var(--gn)' },
  { t: ' ', v: '  use Ash.Resource, domain: MyApp.Finance',     c: 'var(--t3)' },
  { t: ' ', v: '',                                               c: 'var(--t3)' },
  { t: '-', v: '  # TODO: add compliance attribute',            c: 'var(--rd)' },
  { t: '+', v: '  attribute :confirmed_at, :utc_datetime_usec do',c: 'var(--gn)' },
  { t: '+', v: '    allow_nil? false',                           c: 'var(--gn)' },
  { t: '+', v: '    description "Compliance sign-off timestamp"', c: 'var(--gn)' },
  { t: '+', v: '  end',                                          c: 'var(--gn)' },
  { t: ' ', v: 'end',                                            c: 'var(--t3)' },
];

export default function BottomSheet() {
  const bsOpen   = useStore((s) => s.bsOpen);
  const bsNodeId = useStore((s) => s.bsNodeId);
  const bsTab    = useStore((s) => s.bsTab);
  const bsAdr    = useStore((s) => s.bsAdr);
  const setBsTab = useStore((s) => s.setBsTab);
  const setBsAdr = useStore((s) => s.setBsAdr);
  const closeBottomSheet = useStore((s) => s.closeBottomSheet);
  const submitProposal   = useStore((s) => s.submitProposal);

  const n = bsNodeId ? NODES[bsNodeId] : null;

  // Compliance gaps to generate tests for
  const gaps = Object.entries(SCENARIOS).flatMap(([, sc]) =>
    sc.steps.filter((s) => s.gap && s.id === (n?.id ?? '')),
  );

  if (!bsOpen || !n) return null;

  const TABS = [
    { id: 'diff',    label: 'Diff'    },
    { id: 'tests',   label: 'Tests'   },
    { id: 'propose', label: 'Propose' },
  ] as const;

  return (
    <>
      {/* Backdrop */}
      <div
        onClick={closeBottomSheet}
        style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,.4)',
          zIndex: 400, backdropFilter: 'blur(1px)',
        }}
      />

      {/* Sheet */}
      <div
        style={{
          position: 'fixed', bottom: 0, left: 0, right: 0, zIndex: 401,
          background: 'var(--s1)', borderTop: '1px solid var(--b2)',
          height: 380, display: 'flex', flexDirection: 'column',
          boxShadow: '0 -12px 48px rgba(0,0,0,.6)',
        }}
      >
        {/* Title bar */}
        <div style={{
          padding: '10px 16px', borderBottom: '1px solid var(--b1)',
          display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0,
        }}>
          <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--tx)' }}>
            {n.name}
          </span>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, padding: '2px 6px', borderRadius: 3, background: 'var(--s3)', border: '1px solid var(--b2)', color: 'var(--t2)' }}>
            {n.module}
          </span>
          {n.gap && (
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, padding: '2px 6px', borderRadius: 3, background: 'var(--ywb)', border: '1px solid var(--ywbd)', color: 'var(--yw)' }}>
              compliance gap
            </span>
          )}
          <div style={{ flex: 1 }} />
          <button onClick={closeBottomSheet} style={{ background: 'none', border: 'none', color: 'var(--t3)', cursor: 'pointer', fontSize: 13 }}>
            ✕
          </button>
        </div>

        {/* Tabs */}
        <div style={{ display: 'flex', borderBottom: '1px solid var(--b1)', flexShrink: 0 }}>
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setBsTab(tab.id)}
              style={{
                padding: '6px 16px', fontSize: 11, fontWeight: 500, cursor: 'pointer',
                background: 'none', border: 'none',
                borderBottom: `2px solid ${bsTab === tab.id ? 'var(--ac)' : 'transparent'}`,
                color: bsTab === tab.id ? 'var(--tx)' : 'var(--t3)', transition: '.1s',
              }}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Body */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '12px 16px' }}>
          {bsTab === 'diff' && (
            <>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', marginBottom: 8, letterSpacing: '.05em' }}>
                Proposed — {n.module} · <span style={{ color: 'var(--gn)' }}>+4</span> <span style={{ color: 'var(--rd)' }}>-1</span>
              </div>
              <div style={{ background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 5, padding: '8px 10px', fontFamily: 'var(--font-mono)', fontSize: 10, lineHeight: 1.65 }}>
                {DIFF_LINES.map((l, i) => (
                  <div key={i} style={{ display: 'flex', gap: 10 }}>
                    <span style={{ color: l.c, width: 10, flexShrink: 0 }}>{l.t}</span>
                    <span style={{ color: l.c, flex: 1 }}>{l.v}</span>
                  </div>
                ))}
              </div>
            </>
          )}

          {bsTab === 'tests' && (
            <>
              {gaps.length === 0 ? (
                <div style={{ fontSize: 11, color: 'var(--t3)' }}>No coverage gaps detected for this module.</div>
              ) : (
                gaps.map((g, i) => (
                  <div key={i} style={{ marginBottom: 10, background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 5, padding: '9px 11px' }}>
                    <div style={{ fontSize: 10, fontWeight: 600, color: 'var(--yw)', marginBottom: 4 }}>
                      Gap: {g.gapNote}
                    </div>
                    <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, lineHeight: 1.6, color: 'var(--t2)' }}>
                      <span style={{ color: 'var(--pu)' }}>describe</span> &quot;{n.name}/{g.action}&quot; <span style={{ color: 'var(--t3)' }}>do</span><br />
                      &nbsp;&nbsp;<span style={{ color: 'var(--bl)' }}>property</span> &quot;valid inputs&quot; <span style={{ color: 'var(--t3)' }}>do</span><br />
                      &nbsp;&nbsp;&nbsp;&nbsp;<span style={{ color: 'var(--gn)' }}>check</span> all(:valid_input), <span style={{ color: 'var(--yw)' }}>fn</span> input {'->'}<br />
                      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;assert :ok == {n.module}.{g.action}(input)<br />
                      &nbsp;&nbsp;&nbsp;&nbsp;<span style={{ color: 'var(--t3)' }}>end</span><br />
                      &nbsp;&nbsp;<span style={{ color: 'var(--t3)' }}>end</span><br />
                      <span style={{ color: 'var(--t3)' }}>end</span>
                    </div>
                  </div>
                ))
              )}
            </>
          )}

          {bsTab === 'propose' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, maxWidth: 520 }}>
              <div>
                <label style={{ fontSize: 10, color: 'var(--t3)', display: 'block', marginBottom: 4 }}>
                  ADR Reference
                </label>
                <input
                  value={bsAdr}
                  onChange={(e) => setBsAdr(e.target.value)}
                  placeholder="ADR-005"
                  style={{
                    width: '100%', background: 'var(--s2)', border: '1px solid var(--b2)',
                    borderRadius: 'var(--r)', padding: '7px 10px',
                    fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--tx)', outline: 'none',
                  }}
                  onFocus={(e) => (e.currentTarget.style.borderColor = 'var(--ac)')}
                  onBlur={(e) => (e.currentTarget.style.borderColor = 'var(--b2)')}
                />
              </div>
              <div>
                <label style={{ fontSize: 10, color: 'var(--t3)', display: 'block', marginBottom: 4 }}>
                  Description
                </label>
                <textarea
                  rows={4}
                  placeholder={`Describe the change to ${n.name}…`}
                  style={{
                    width: '100%', background: 'var(--s2)', border: '1px solid var(--b2)',
                    borderRadius: 'var(--r)', padding: '7px 10px',
                    fontFamily: 'var(--font-sans)', fontSize: 12, color: 'var(--tx)', outline: 'none',
                    resize: 'none', lineHeight: 1.5,
                  }}
                  onFocus={(e) => (e.currentTarget.style.borderColor = 'var(--ac)')}
                  onBlur={(e) => (e.currentTarget.style.borderColor = 'var(--b2)')}
                />
              </div>
            </div>
          )}
        </div>

        {/* CTA row */}
        <div style={{ padding: '10px 16px 14px', borderTop: '1px solid var(--b1)', display: 'flex', gap: 8, justifyContent: 'flex-end', flexShrink: 0 }}>
          <button style={BTN_G} onClick={closeBottomSheet}>Discard</button>
          <button style={BTN_P} onClick={submitProposal}>
            Submit proposal
          </button>
        </div>
      </div>
    </>
  );
}
