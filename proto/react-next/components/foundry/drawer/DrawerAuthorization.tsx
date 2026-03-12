'use client';

import { useStore } from '@/lib/store';
import { NODES } from '@/lib/data';

/**
 * Authorization matrix tab for Resource nodes (ADR-016).
 * Placeholder until policy introspection exists.
 */
export default function DrawerAuthorization() {
  const selectedId = useStore((s) => s.selectedId);

  const n = selectedId ? NODES[selectedId] : null;
  if (!n || n.type !== 'resource') return null;

  // Placeholder actor/action matrix
  const actors = ['Admin', 'Player', 'System'];
  const actions = n.actions?.map((a) => a.n) ?? ['read', 'create', 'update', 'destroy'];

  return (
    <div style={{ flex: 1, overflowY: 'auto', padding: '10px 14px' }}>
      <div style={{ fontSize: 9, fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 10 }}>
        Authorization Matrix
      </div>
      <div style={{ fontSize: 10, color: 'var(--t3)', marginBottom: 12 }}>
        Actor / action policy matrix (placeholder until policy introspection)
      </div>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 10 }}>
          <thead>
            <tr>
              <th style={{ padding: '6px 8px', textAlign: 'left', borderBottom: '1px solid var(--b2)', color: 'var(--t3)', fontWeight: 500 }}>
                Actor
              </th>
              {actions.map((a) => (
                <th key={a} style={{ padding: '6px 8px', textAlign: 'center', borderBottom: '1px solid var(--b2)', color: 'var(--t3)', fontWeight: 500 }}>
                  {a}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {actors.map((actor) => (
              <tr key={actor} style={{ borderBottom: '1px solid var(--b1)' }}>
                <td style={{ padding: '6px 8px', color: 'var(--t2)' }}>{actor}</td>
                {actions.map((a) => (
                  <td key={a} style={{ padding: '6px 8px', textAlign: 'center', color: 'var(--t3)' }}>
                    —
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
