'use client';

import { useStore } from '@/lib/store';
import { NODES, EDGES, TYPE_ICON, TYPE_COLOR } from '@/lib/data';
import { covColor } from '@/lib/graph-utils';

/**
 * System Map table view for accessibility (ADR-012, WCAG 2.1 AA).
 * Lists nodes and edges in navigable format.
 */
export default function SystemMapTable() {
  const selectNode = useStore((s) => s.selectNode);
  const selectedId = useStore((s) => s.selectedId);

  const nodes = Object.values(NODES);

  return (
    <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
      <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: 'var(--tx)' }}>
        System Map — Table View
      </div>
      <div style={{ fontSize: 11, color: 'var(--t3)', marginBottom: 16 }}>
        Navigable list of nodes and edges. Use graph view for spatial layout.
      </div>

      <section style={{ marginBottom: 24 }}>
        <h2 style={{ fontSize: 12, fontWeight: 600, color: 'var(--t2)', marginBottom: 8 }}>Nodes</h2>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 11 }}>
          <thead>
            <tr style={{ background: 'var(--s2)', borderBottom: '1px solid var(--b2)' }}>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Type</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Name</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Domain</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Coverage</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Requirements</th>
            </tr>
          </thead>
          <tbody>
            {nodes.map((n) => (
              <tr
                key={n.id}
                onClick={() => selectNode(n.id)}
                style={{
                  borderBottom: '1px solid var(--b1)',
                  cursor: 'pointer',
                  background: selectedId === n.id ? 'var(--acb)' : 'transparent',
                }}
              >
                <td style={{ padding: '8px 12px' }}>
                  <span style={{ color: TYPE_COLOR[n.type] }}>{TYPE_ICON[n.type] ?? '?'}</span>
                  <span style={{ marginLeft: 4, color: 'var(--t2)' }}>{n.type}</span>
                </td>
                <td style={{ padding: '8px 12px', color: 'var(--tx)', fontWeight: 500 }}>{n.name}</td>
                <td style={{ padding: '8px 12px', color: 'var(--t2)' }}>{n.domain}</td>
                <td style={{ padding: '8px 12px', color: covColor(n.cov), fontFamily: 'var(--font-mono)' }}>{n.cov}%</td>
                <td style={{ padding: '8px 12px' }}>
                  {n.reqs.length > 0 ? n.reqs.map((r) => (
                    <span key={r} style={{ marginRight: 4, fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--ac2)' }}>{r}</span>
                  )) : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2 style={{ fontSize: 12, fontWeight: 600, color: 'var(--t2)', marginBottom: 8 }}>Edges</h2>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 11 }}>
          <thead>
            <tr style={{ background: 'var(--s2)', borderBottom: '1px solid var(--b2)' }}>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>From</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>To</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Relation</th>
            </tr>
          </thead>
          <tbody>
            {EDGES.map((e, i) => (
              <tr key={i} style={{ borderBottom: '1px solid var(--b1)' }}>
                <td style={{ padding: '8px 12px', color: 'var(--t2)' }}>{NODES[e.f]?.name ?? e.f}</td>
                <td style={{ padding: '8px 12px', color: 'var(--t2)' }}>{NODES[e.t]?.name ?? e.t}</td>
                <td style={{ padding: '8px 12px', fontFamily: 'var(--font-mono)', color: 'var(--t3)' }}>{e.r}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}
