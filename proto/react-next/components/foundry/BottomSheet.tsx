'use client';

import { useStore } from '@/lib/store';
import { NODES, SCENARIOS } from '@/lib/data';
import { inferChangeClass, getApprovalMessage } from '@/lib/change-class';
import type { GraphNode } from '@/lib/types';

const CHANGE_CLASS_COLOR: Record<string, string> = {
  sensitive: 'var(--rd)',
  compliance: 'var(--yw)',
  behavioral: 'var(--gn)',
  structural: 'var(--bl)',
};

function ApprovalFooter({ node }: { node: GraphNode }) {
  const cls = inferChangeClass(node);
  const msg = getApprovalMessage(node);
  const color = CHANGE_CLASS_COLOR[cls] ?? 'var(--t2)';
  return (
    <div style={{
      padding: '8px 16px', borderTop: '1px solid var(--b1)', background: 'var(--s2)',
      fontSize: 10, color: 'var(--t3)', flexShrink: 0,
    }}>
      <span style={{ fontWeight: 500, color: 'var(--t2)' }}>Change class:</span>{' '}
      <span style={{ color }}>:{cls}</span>
      {' — '}
      {msg}
    </div>
  );
}

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
    { id: 'diff',      label: 'Code Changes' },
    { id: 'migration', label: 'Migration'    },
    { id: 'lint',      label: 'Lint'         },
    { id: 'impact',    label: 'Impact'       },
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

          {bsTab === 'migration' && (
            <div style={{ fontSize: 11, color: 'var(--t3)' }}>
              {n.pm ? (
                <div style={{ background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 5, padding: '10px 12px', fontFamily: 'var(--font-mono)', fontSize: 10, lineHeight: 1.6 }}>
                  <div style={{ color: 'var(--yw)', marginBottom: 6 }}>Pending migration</div>
                  <div>create table(:spending_limits) do</div>
                  <div style={{ paddingLeft: 12 }}>add :confirmed_at, :utc_datetime_usec</div>
                  <div>end</div>
                </div>
              ) : (
                <div>No migration required for this proposal.</div>
              )}
            </div>
          )}

          {bsTab === 'lint' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <div style={{ fontSize: 11, color: 'var(--gn)' }}>No lint violations.</div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t4)' }}>
                Credo · ElixirLS · Compiler
              </div>
            </div>
          )}

          {bsTab === 'impact' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <div style={{ fontSize: 11, color: 'var(--t2)' }}>
                Affected: <span style={{ color: 'var(--ac)' }}>WithdrawalTransfer</span>, <span style={{ color: 'var(--ac)' }}>SpendingLimit</span>
              </div>
              <div style={{ fontSize: 10, color: 'var(--t3)' }}>
                Downstream: 2 transfers, 1 rule. No breaking API changes.
              </div>
            </div>
          )}
        </div>

        {/* Approval footer (ADR-012) */}
        <ApprovalFooter node={n} />

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
