'use client';

import { useStore } from '@/lib/store';
import { NODES, REQ_META } from '@/lib/data';

export default function CompliancePanel() {
  const openDocPreview = useStore((s) => s.openDocPreview);
  const rows = Object.values(NODES)
    .filter((n) => n.reqs.length > 0)
    .flatMap((n) =>
      n.reqs.map((r) => ({
        module: n.name,
        req: r,
        label: REQ_META[r]?.label ?? '—',
        gap: n.gap,
      }))
    );

  return (
    <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
      <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: 'var(--tx)' }}>
        Compliance Matrix
      </div>
      <div style={{ fontSize: 11, color: 'var(--t3)', marginBottom: 16 }}>
        Requirement coverage by module. Data from <code>mix foundry.compliance.check</code>.
      </div>
      <div style={{ overflowX: 'auto', border: '1px solid var(--b2)', borderRadius: 6 }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 11 }}>
          <thead>
            <tr style={{ background: 'var(--s2)', borderBottom: '1px solid var(--b2)' }}>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Module</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Requirement</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Label</th>
              <th style={{ padding: '8px 12px', textAlign: 'left', color: 'var(--t3)', fontWeight: 500 }}>Status</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr>
                <td colSpan={4} style={{ padding: 24, textAlign: 'center', color: 'var(--t3)', fontSize: 11 }}>
                  No compliance requirements declared. Add regulation files to <code>docs/regulations/</code> to populate this matrix.
                </td>
              </tr>
            ) : (
              rows.map((row, i) => (
                <tr key={i} style={{ borderBottom: '1px solid var(--b1)' }}>
                  <td style={{ padding: '8px 12px', color: 'var(--t2)' }}>{row.module}</td>
                  <td
                    style={{ padding: '8px 12px', fontFamily: 'var(--font-mono)', color: 'var(--ac2)', cursor: 'pointer', textDecoration: 'underline', textUnderlineOffset: 2 }}
                    role="button"
                    tabIndex={0}
                    onClick={() => openDocPreview('regulation', row.req)}
                    onKeyDown={(e) => e.key === 'Enter' && openDocPreview('regulation', row.req)}
                  >
                    {row.req}
                  </td>
                  <td
                    style={{ padding: '8px 12px', color: 'var(--t2)', cursor: 'pointer', textDecoration: 'underline', textUnderlineOffset: 2 }}
                    role="button"
                    tabIndex={0}
                    onClick={() => openDocPreview('regulation', row.req)}
                    onKeyDown={(e) => e.key === 'Enter' && openDocPreview('regulation', row.req)}
                  >
                    {row.label}
                  </td>
                  <td style={{ padding: '8px 12px' }}>
                    <span style={{
                      padding: '2px 6px', borderRadius: 3, fontSize: 9,
                      background: row.gap ? 'var(--ywb)' : 'var(--gnb)',
                      color: row.gap ? 'var(--yw)' : 'var(--gn)',
                    }}>
                      {row.gap ? 'Gap' : 'Covered'}
                    </span>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
