'use client';

import { useStore } from '@/lib/store';
import { NODES } from '@/lib/data';

const QUICK_ACTIONS = [
  { label: 'Propose attribute addition', sub: 'Add a new attribute to this resource' },
  { label: 'Generate property tests',    sub: 'Scaffold StreamData property tests'   },
  { label: 'Generate scenario tests',    sub: 'Scaffold compliance scenario tests'   },
  { label: 'Add compliance requirement', sub: 'Link a regulatory requirement'        },
  { label: 'Create runbook',             sub: 'Generate a runbook template'          },
  { label: 'View impact analysis',       sub: 'What changes if this module is modified' },
] as const;

const BTN_P: React.CSSProperties = {
  display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5,
  padding: '8px 12px', background: 'var(--ac)', border: 'none', borderRadius: 'var(--r)',
  fontFamily: 'var(--font-sans)', fontSize: 12, fontWeight: 500, color: '#fff',
  cursor: 'pointer', width: '100%', transition: '.12s',
};

export default function DrawerActions() {
  const selectedId       = useStore((s) => s.selectedId);
  const openBottomSheet  = useStore((s) => s.openBottomSheet);

  const n = selectedId ? NODES[selectedId] : null;
  if (!n) return null;

  return (
    <>
      <div style={{ flex: 1, overflowY: 'auto' }}>
        <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
          <div style={{
            fontSize: 9, fontWeight: 600, letterSpacing: '.12em',
            textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 9,
          }}>
            Quick Actions
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 4 }}>
            {QUICK_ACTIONS.map((a) => (
              <button
                key={a.label}
                onClick={() => openBottomSheet(n.id)}
                style={{
                  background: 'var(--s2)', border: '1px solid var(--b2)', borderRadius: 5,
                  padding: '6px 8px', fontSize: 10, color: 'var(--t2)',
                  cursor: 'pointer', textAlign: 'left', transition: '.1s', lineHeight: 1.4,
                }}
                onMouseEnter={(e) => {
                  (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b3)';
                  (e.currentTarget as HTMLButtonElement).style.color = 'var(--tx)';
                }}
                onMouseLeave={(e) => {
                  (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b2)';
                  (e.currentTarget as HTMLButtonElement).style.color = 'var(--t2)';
                }}
              >
                <strong style={{ color: 'var(--tx)', display: 'block', marginBottom: 1 }}>{a.label}</strong>
                {a.sub}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div style={{ padding: '10px 14px 14px', borderTop: '1px solid var(--b1)', flexShrink: 0 }}>
        <button style={BTN_P} onClick={() => openBottomSheet(n.id)}>
          Open proposal panel
        </button>
      </div>
    </>
  );
}
