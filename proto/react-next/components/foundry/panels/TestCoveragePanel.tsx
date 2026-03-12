'use client';

import { NODES, DOMAIN_ORDER } from '@/lib/data';
import { covColor } from '@/lib/graph-utils';

export default function TestCoveragePanel() {
  const byDomain = DOMAIN_ORDER.map((domain) => {
    const nodes = Object.values(NODES).filter((n) => n.domain === domain);
    const avg = nodes.length ? Math.round(nodes.reduce((a, n) => a + n.cov, 0) / nodes.length) : 0;
    return { domain, nodes, avg };
  });

  return (
    <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
      <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: 'var(--tx)' }}>
        Test Coverage Map
      </div>
      <div style={{ fontSize: 11, color: 'var(--t3)', marginBottom: 16 }}>
        Coverage by domain and module. Property / scenario / E2E breakdown.
      </div>
      {byDomain.every((d) => d.nodes.length === 0) ? (
        <div style={{ padding: 24, textAlign: 'center', color: 'var(--t3)', fontSize: 11 }}>
          No test results found. Run <code>mix test</code> to populate coverage data.
        </div>
      ) : (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        {byDomain.filter((d) => d.nodes.length > 0).map(({ domain, nodes, avg }) => (
          <section key={domain}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--t2)' }}>{domain}</span>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: covColor(avg) }}>{avg}%</span>
              <div style={{ flex: 1, height: 4, background: 'var(--s4)', borderRadius: 99, overflow: 'hidden', maxWidth: 100 }}>
                <div style={{ width: `${avg}%`, height: '100%', background: covColor(avg), borderRadius: 99 }} />
              </div>
            </div>
            <div style={{ background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 6, padding: 8 }}>
              {nodes.map((n) => (
                <div key={n.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '4px 8px', fontSize: 10 }}>
                  <span style={{ flex: 1, color: 'var(--t2)' }}>{n.name}</span>
                  <span style={{ color: covColor(n.cov), fontFamily: 'var(--font-mono)', width: 32 }}>{n.cov}%</span>
                  <span style={{ display: 'flex', gap: 4 }}>
                    {[n.tests.p, n.tests.s, n.tests.e].map((v, i) => (
                      <span key={i} style={{ color: v ? 'var(--gn)' : 'var(--t4)', fontSize: 9 }}>{v ? '✓' : '—'}</span>
                    ))}
                  </span>
                </div>
              ))}
            </div>
          </section>
        ))}
      </div>
      )}
    </div>
  );
}
