'use client';

import { useStore } from '@/lib/store';
import { NODES, SCENARIOS } from '@/lib/data';

const BTN_T: React.CSSProperties = {
  display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5,
  padding: '8px 12px',
  background: 'rgba(245,158,11,.08)', border: '1px solid var(--ywbd)', borderRadius: 'var(--r)',
  fontFamily: 'var(--font-sans)', fontSize: 12, color: 'var(--yw)',
  cursor: 'pointer', width: '100%', transition: '.12s',
};

export default function DrawerFlow() {
  const selectedId = useStore((s) => s.selectedId);
  const selectNode = useStore((s) => s.selectNode);
  const setLens    = useStore((s) => s.setLens);
  const pickScenario = useStore((s) => s.pickScenario);

  const n = selectedId ? NODES[selectedId] : null;
  if (!n) return null;

  // Scenarios that involve this node
  const relevant = Object.entries(SCENARIOS).filter(([, sc]) =>
    sc.steps.some((s) => s.id === n.id),
  );

  function traceScenario(sid: string) {
    setLens('trc');
    pickScenario(sid);
  }

  return (
    <>
      <div style={{ flex: 1, overflowY: 'auto' }}>
        <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
          <div style={{ fontSize: 11, color: 'var(--t2)', lineHeight: 1.6, marginBottom: 10 }}>
            Scenarios that involve{' '}
            <strong style={{ color: 'var(--tx)' }}>{n.name}</strong>. Click a step to highlight it on the canvas.
          </div>

          {relevant.length === 0 ? (
            <div style={{ fontSize: 11, color: 'var(--t3)' }}>No scenarios defined for this module.</div>
          ) : (
            relevant.map(([sid, sc]) => (
              <div key={sid} style={{ marginBottom: 12 }}>
                <div style={{ fontSize: 10, fontWeight: 600, color: 'var(--t2)', marginBottom: 5 }}>
                  {sc.label}
                </div>
                {sc.steps.map((step, i) => {
                  const stepNode = NODES[step.id];
                  const isThis = step.id === n.id;
                  return (
                    <div
                      key={step.id + i}
                      role="button"
                      tabIndex={0}
                      onClick={() => selectNode(step.id)}
                      onKeyDown={(e) => e.key === 'Enter' && selectNode(step.id)}
                      style={{
                        display: 'flex', alignItems: 'flex-start', gap: 8,
                        padding: '7px 8px',
                        background: isThis ? 'rgba(245,158,11,.06)' : 'var(--s2)',
                        border: `1px solid ${isThis ? 'var(--ywbd)' : 'var(--b1)'}`,
                        borderRadius: 5, marginBottom: 4, cursor: 'pointer', transition: '.1s',
                      }}
                    >
                      {/* Step number */}
                      <div style={{
                        width: 20, height: 20, borderRadius: '50%', flexShrink: 0,
                        background: isThis ? 'var(--ywb)' : 'var(--s3)',
                        border: `1px solid ${isThis ? 'var(--ywbd)' : 'var(--b2)'}`,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        fontFamily: 'var(--font-mono)', fontSize: 9,
                        color: isThis ? 'var(--yw)' : 'var(--t2)',
                        marginTop: 1,
                      }}>
                        {i + 1}
                      </div>
                      {/* Body */}
                      <div style={{ flex: 1 }}>
                        <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--tx)', display: 'flex', alignItems: 'center', gap: 4 }}>
                          {stepNode?.name ?? step.id}
                          <span style={{
                            fontFamily: 'var(--font-mono)', fontSize: 8, padding: '1px 4px', borderRadius: 2, marginLeft: 5,
                            background: step.gap ? 'var(--ywb)' : 'var(--gnb)',
                            color: step.gap ? 'var(--yw)' : 'var(--gn)',
                          }}>
                            {step.gap ? 'gap' : 'ok'}
                          </span>
                        </div>
                        <div style={{ fontSize: 10, color: 'var(--t3)', marginTop: 2, lineHeight: 1.4 }}>
                          {step.action} — {step.note}
                        </div>
                        {step.gap && step.gapNote && (
                          <div style={{ fontSize: 9, color: 'var(--yw)', marginTop: 2 }}>
                            ⚠ {step.gapNote}
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            ))
          )}
        </div>
      </div>

      {/* CTA */}
      {relevant.length > 0 && (
        <div style={{ padding: '10px 14px 14px', borderTop: '1px solid var(--b1)', flexShrink: 0 }}>
          <button style={BTN_T} onClick={() => traceScenario(relevant[0][0])}>
            &#9654; Trace {SCENARIOS[relevant[0][0]].label}
          </button>
        </div>
      )}
    </>
  );
}
