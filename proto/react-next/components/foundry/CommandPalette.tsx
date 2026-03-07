'use client';

import { useState, useEffect, useRef } from 'react';
import { useStore } from '@/lib/store';
import { NODES, REQ_META, TYPE_COLOR, TYPE_ABBR } from '@/lib/data';

// ─── Palette item types ───────────────────────────────────────────────────────

type PalItem = {
  id: string;
  label: string;
  type: 'module' | 'req' | 'adr';
  iconText: string;
  iconColor: string;
  action: () => void;
};

const ADR_IDS = Array.from({ length: 15 }, (_, i) =>
  `ADR-${String(i + 1).padStart(3, '0')}`,
);

// ─── Icon background color by type ───────────────────────────────────────────

const ICON_BG: Record<string, string> = {
  resource: 'var(--blb)',
  transfer: 'var(--gnb)',
  rule:     'var(--ywb)',
  reactor:  'var(--pub)',
};

// ─── Component ───────────────────────────────────────────────────────────────

export default function CommandPalette() {
  const paletteOpen  = useStore((s) => s.paletteOpen);
  const closePalette = useStore((s) => s.closePalette);
  const selectNode   = useStore((s) => s.selectNode);
  const showToast    = useStore((s) => s.showToast);

  const [query, setQuery] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  // Build full item list once
  const allItems: PalItem[] = [
    ...Object.values(NODES).map((n) => ({
      id: n.id,
      label: n.name,
      type: 'module' as const,
      iconText: TYPE_ABBR[n.type],
      iconColor: TYPE_COLOR[n.type],
      action: () => { closePalette(); selectNode(n.id); },
    })),
    ...Object.keys(REQ_META).map((r) => ({
      id: r,
      label: `${r} — ${REQ_META[r].label}`,
      type: 'req' as const,
      iconText: 'R',
      iconColor: 'var(--yw)',
      action: () => { closePalette(); showToast(`${r}: ${REQ_META[r].label}`); },
    })),
    ...ADR_IDS.map((a) => ({
      id: a,
      label: a,
      type: 'adr' as const,
      iconText: 'A',
      iconColor: 'var(--t2)',
      action: () => { closePalette(); showToast(`Opening ${a}…`); },
    })),
  ];

  // Filter on query
  const lq = query.toLowerCase();
  const filtered = lq
    ? allItems.filter((i) => i.label.toLowerCase().includes(lq)).slice(0, 14)
    : allItems.slice(0, 14);

  const grouped = {
    module: filtered.filter((i) => i.type === 'module'),
    req:    filtered.filter((i) => i.type === 'req'),
    adr:    filtered.filter((i) => i.type === 'adr'),
  };
  const GROUP_LABELS = { module: 'Modules', req: 'Requirements', adr: 'ADRs' };

  // Focus input when opened
  useEffect(() => {
    if (paletteOpen) {
      setQuery('');
      setTimeout(() => inputRef.current?.focus(), 40);
    }
  }, [paletteOpen]);

  // Close on Escape
  useEffect(() => {
    function handler(e: KeyboardEvent) {
      if (e.key === 'Escape') closePalette();
    }
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [closePalette]);

  if (!paletteOpen) return null;

  const nodeTypeKey = (item: PalItem) => {
    if (item.type !== 'module') return null;
    const n = NODES[item.id];
    return n?.type ?? null;
  };

  return (
    <>
      {/* Backdrop */}
      <div
        onClick={closePalette}
        style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,.65)',
          zIndex: 500, backdropFilter: 'blur(3px)',
          display: 'flex', alignItems: 'flex-start', justifyContent: 'center',
          paddingTop: '14vh',
        }}
      >
        {/* Panel — stop propagation so clicks inside don't close */}
        <div
          onClick={(e) => e.stopPropagation()}
          style={{
            width: 540, background: 'var(--s2)', border: '1px solid var(--b3)',
            borderRadius: 10, overflow: 'hidden',
            boxShadow: '0 28px 72px rgba(0,0,0,.7)',
          }}
        >
          {/* Search input */}
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Jump to module, ADR, requirement, scenario…"
            style={{
              width: '100%', background: 'none', border: 'none',
              borderBottom: '1px solid var(--b1)', padding: '13px 16px',
              fontFamily: 'var(--font-sans)', fontSize: 14, color: 'var(--tx)', outline: 'none',
            }}
          />

          {/* Results */}
          <div style={{ maxHeight: 380, overflowY: 'auto' }}>
            {filtered.length === 0 ? (
              <div style={{ padding: '20px 16px', textAlign: 'center', fontSize: 12, color: 'var(--t3)' }}>
                No results
              </div>
            ) : (
              (['module', 'req', 'adr'] as const).map((gk) => {
                const items = grouped[gk];
                if (!items.length) return null;
                return (
                  <div key={gk} style={{ padding: '6px 0' }}>
                    <div style={{ padding: '4px 16px', fontSize: 9, fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', color: 'var(--t3)' }}>
                      {GROUP_LABELS[gk]}
                    </div>
                    {items.slice(0, 6).map((item) => {
                      const nType = nodeTypeKey(item);
                      const bg = nType ? ICON_BG[nType] : 'var(--s3)';
                      return (
                        <button
                          key={item.id}
                          onClick={item.action}
                          style={{
                            width: '100%', padding: '8px 16px',
                            display: 'flex', alignItems: 'center', gap: 10,
                            cursor: 'pointer', fontSize: 12, background: 'none',
                            border: 'none', transition: '.08s', textAlign: 'left',
                          }}
                          onMouseEnter={(e) => (e.currentTarget.style.background = 'var(--s3)')}
                          onMouseLeave={(e) => (e.currentTarget.style.background = 'none')}
                        >
                          <div style={{
                            width: 26, height: 26, borderRadius: 5, flexShrink: 0,
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            fontFamily: 'var(--font-mono)', fontSize: 10, fontWeight: 600,
                            background: bg, color: item.iconColor,
                          }}>
                            {item.iconText}
                          </div>
                          <span style={{ color: 'var(--tx)', flex: 1 }}>{item.label}</span>
                          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)' }}>{item.type}</span>
                        </button>
                      );
                    })}
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>
    </>
  );
}
