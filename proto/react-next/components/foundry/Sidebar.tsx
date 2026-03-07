'use client';

import { useState } from 'react';
import { useStore } from '@/lib/store';
import { NODES, DOMAIN_ORDER, TYPE_ABBR, TYPE_COLOR } from '@/lib/data';

const DOMAIN_ABBR: Record<string, string> = {
  Finance: 'FIN',
  Identity: 'IDN',
  Compliance: 'CMP',
  Game: 'GAM',
};

export default function Sidebar() {
  const [query, setQuery] = useState('');
  const selectedId = useStore((s) => s.selectedId);
  const traceSet = useStore((s) => s.traceSet);
  const selectNode = useStore((s) => s.selectNode);

  const lf = query.toLowerCase();

  const gapCount = Object.values(NODES).filter((n) => n.gap).length;
  const migrCount = Object.values(NODES).filter((n) => n.pm).length;

  return (
    <aside
      style={{
        width: 214, minWidth: 214, background: 'var(--s1)',
        borderRight: '1px solid var(--b1)', display: 'flex',
        flexDirection: 'column', overflow: 'hidden', flexShrink: 0,
      }}
    >
      {/* Header */}
      <div style={{ padding: '10px 12px 8px', borderBottom: '1px solid var(--b1)' }}>
        <div style={{ fontSize: 9, fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 7 }}>
          Domains
        </div>

        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Filter modules…"
          style={{
            width: '100%', background: 'var(--s2)', border: '1px solid var(--b2)',
            borderRadius: 'var(--r)', padding: '5px 9px', fontFamily: 'var(--font-sans)',
            fontSize: 12, color: 'var(--tx)', outline: 'none', transition: '.12s',
          }}
          onFocus={(e) => (e.currentTarget.style.borderColor = 'var(--ac)')}
          onBlur={(e) => (e.currentTarget.style.borderColor = 'var(--b2)')}
        />

        {/* Counts */}
        <div style={{ display: 'flex', gap: 5, marginTop: 7 }}>
          {[
            { n: Object.keys(NODES).length, l: 'modules', color: 'var(--tx)' },
            { n: gapCount, l: 'gaps', color: 'var(--rd)' },
            { n: migrCount, l: 'migr', color: 'var(--yw)' },
          ].map(({ n, l, color }) => (
            <div key={l} style={{ flex: 1, background: 'var(--s2)', border: '1px solid var(--b1)', borderRadius: 5, padding: '5px 6px', textAlign: 'center' }}>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: 14, fontWeight: 600, lineHeight: 1.1, color }}>{n}</div>
              <div style={{ fontSize: 9, color: 'var(--t3)', marginTop: 1 }}>{l}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Node list */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '4px 0 12px' }}>
        {DOMAIN_ORDER.map((domain) => {
          const nodes = Object.values(NODES).filter(
            (n) => n.domain === domain && (!lf || n.name.toLowerCase().includes(lf) || domain.toLowerCase().includes(lf))
          );
          if (!nodes.length) return null;

          return (
            <div key={domain}>
              {/* Domain header */}
              <div style={{
                padding: '8px 12px 3px', fontSize: 9, fontWeight: 600, letterSpacing: '.12em',
                textTransform: 'uppercase', color: 'var(--t3)', display: 'flex', alignItems: 'center', gap: 6,
              }}>
                {DOMAIN_ABBR[domain] || domain}
                <div style={{ flex: 1, height: 1, background: 'var(--b1)' }} />
              </div>

              {nodes.map((n) => {
                const isSelected = selectedId === n.id;
                const isTrace = traceSet.has(n.id);
                const pipColor = n.gap ? 'var(--yw)' : n.sensitive ? 'var(--rd)' : 'var(--gn)';

                return (
                  <div
                    key={n.id}
                    role="button"
                    tabIndex={0}
                    onClick={() => selectNode(n.id)}
                    onKeyDown={(e) => e.key === 'Enter' && selectNode(n.id)}
                    style={{
                      padding: '5px 12px', display: 'flex', alignItems: 'center', gap: 7,
                      cursor: 'pointer',
                      borderLeft: `2px solid ${isSelected ? 'var(--ac)' : isTrace ? 'var(--yw)' : 'transparent'}`,
                      background: isSelected ? 'var(--acb)' : isTrace ? 'rgba(245,158,11,.06)' : 'none',
                      transition: '.08s',
                    }}
                    onMouseEnter={(e) => {
                      if (!isSelected) (e.currentTarget as HTMLDivElement).style.background = 'var(--s2)';
                    }}
                    onMouseLeave={(e) => {
                      (e.currentTarget as HTMLDivElement).style.background = isSelected ? 'var(--acb)' : isTrace ? 'rgba(245,158,11,.06)' : 'none';
                    }}
                  >
                    {/* Type icon */}
                    <div style={{
                      width: 18, height: 18, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontFamily: 'var(--font-mono)', fontSize: 7, fontWeight: 600, borderRadius: 3,
                      background: TYPE_COLOR[n.type] + '1a', color: TYPE_COLOR[n.type],
                    }}>
                      {TYPE_ABBR[n.type]}
                    </div>

                    <span style={{ fontSize: 11, color: 'var(--tx)', flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {n.name}
                    </span>

                    {/* Status pip */}
                    <div style={{ width: 5, height: 5, borderRadius: '50%', flexShrink: 0, background: pipColor }} />
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>
    </aside>
  );
}
