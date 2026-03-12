'use client';

import { NODES } from '@/lib/data';

export default function OperationsPanel() {
  const obanNodes = Object.values(NODES).filter((n) => n.oban?.length);
  const transfers = Object.values(NODES).filter((n) => n.type === 'transfer' || n.type === 'reactor');

  return (
    <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
      <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: 'var(--tx)' }}>
        Operations Board
      </div>
      <div style={{ fontSize: 11, color: 'var(--t3)', marginBottom: 16 }}>
        Oban queues and transfer/reactor status. Placeholder until backend integration.
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <section>
          <div style={{ fontSize: 10, fontWeight: 600, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 8 }}>
            Oban Queues
          </div>
          <div style={{ background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 6, padding: 12 }}>
            {obanNodes.length === 0 ? (
              <div style={{ color: 'var(--t3)', fontSize: 11 }}>No runbook links found. Add <code>@runbook</code> declarations to Reactor modules to populate this board.</div>
            ) : (
              obanNodes.map((n) => (
                <div key={n.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', borderBottom: '1px solid var(--b1)' }}>
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--ac2)' }}>{n.oban![0]}</span>
                  <span style={{ color: 'var(--t2)', fontSize: 11 }}>{n.name}</span>
                </div>
              ))
            )}
          </div>
        </section>
        <section>
          <div style={{ fontSize: 10, fontWeight: 600, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 8 }}>
            Transfers / Reactors
          </div>
          <div style={{ background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 6, padding: 12 }}>
            {transfers.map((n) => (
              <div key={n.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', borderBottom: '1px solid var(--b1)' }}>
                <span style={{ color: 'var(--t2)', fontSize: 11 }}>{n.name}</span>
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t4)' }}>{n.type}</span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
