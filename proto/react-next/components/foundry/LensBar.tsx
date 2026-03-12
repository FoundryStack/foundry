'use client';

import { useStore } from '@/lib/store';
import type { Lens } from '@/lib/types';
import { SCENARIOS } from '@/lib/data';

type LensConfig = {
  id: Lens;
  label: string;
  dot?: string;
};

// ADR-016: 4 canvas modes — Default, Scenario trace, Authorization, Config view
const LENSES: LensConfig[] = [
  { id: 'default', label: 'Default',        dot: 'var(--ac2)' },
  { id: 'trc',     label: 'Scenario trace', dot: 'var(--yw)' },
  { id: 'auth',    label: 'Authorization',  dot: 'var(--rd)' },
  { id: 'cfg',     label: 'Config view',    dot: 'var(--pu)' },
];

const ACTIVE: Partial<Record<Lens, { color: string; border: string; bg?: string }>> = {
  default: { color: 'var(--ac2)', border: 'var(--acbd)' },
  trc:     { color: 'var(--yw)',  border: 'var(--ywbd)', bg: 'rgba(245,158,11,.06)' },
  auth:    { color: 'var(--rd)',  border: 'var(--rdbd)' },
  cfg:     { color: 'var(--pu)',  border: 'var(--pubd)' },
};

export default function LensBar() {
  const lens = useStore((s) => s.lens);
  const setLens = useStore((s) => s.setLens);
  const traceId = useStore((s) => s.traceId);
  const traceGaps = useStore((s) => s.traceGaps);
  const pickScenario = useStore((s) => s.pickScenario);
  const clearTrace = useStore((s) => s.clearTrace);
  const systemMapView = useStore((s) => s.systemMapView);
  const setSystemMapView = useStore((s) => s.setSystemMapView);

  const sc = traceId ? SCENARIOS[traceId] : null;
  const gaps = sc ? sc.steps.filter((s) => s.gap).length : 0;
  const showBar = lens === 'trc' || lens === 'auth' || lens === 'cfg';

  return (
    <div style={{ flexShrink: 0 }}>
      {/* Lens buttons row — ADR-016: 4 canvas modes */}
      <div style={{
        height: 38, background: 'var(--s1)', borderBottom: '1px solid var(--b1)',
        display: 'flex', alignItems: 'center', padding: '0 14px', gap: 4,
      }}>
        {LENSES.map(({ id, label, dot }) => {
          const active = lens === id;
          const ac = ACTIVE[id];
          return (
            <button
              key={id}
              onClick={() => setLens(id)}
              style={{
                padding: '4px 10px', borderRadius: 4, fontSize: 11, fontWeight: 500, cursor: 'pointer',
                border: `1px solid ${active ? (ac?.border ?? 'var(--b3)') : 'transparent'}`,
                background: active ? 'var(--s3)' : 'none',
                color: active ? (ac?.color ?? 'var(--tx)') : 'var(--t3)',
                transition: '.1s', display: 'flex', alignItems: 'center', gap: 5, whiteSpace: 'nowrap',
              }}
            >
              {dot && <span style={{ width: 7, height: 7, borderRadius: '50%', background: dot }} />}
              {label}
            </button>
          );
        })}

        <div style={{ width: 1, height: 18, background: 'var(--b2)', margin: '0 4px' }} />

        <button
          onClick={() => setSystemMapView(systemMapView === 'graph' ? 'table' : 'graph')}
          style={{
            padding: '4px 10px', borderRadius: 4, fontSize: 11, fontWeight: 500, cursor: 'pointer',
            border: `1px solid ${systemMapView === 'table' ? 'var(--acbd)' : 'transparent'}`,
            background: systemMapView === 'table' ? 'var(--acb)' : 'none',
            color: systemMapView === 'table' ? 'var(--ac2)' : 'var(--t3)',
            transition: '.1s', whiteSpace: 'nowrap',
          }}
        >
          {systemMapView === 'graph' ? 'Table view' : 'Graph view'}
        </button>

        <div style={{ flex: 1 }} />
      </div>

      {/* Context bar */}
      {showBar && (
        <div style={{
          padding: '8px 14px', background: 'rgba(245,158,11,.05)',
          borderBottom: '1px solid rgba(245,158,11,.15)',
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          {lens === 'trc' && (
            <>
              <span style={{ fontSize: 11, color: 'var(--yw)', fontWeight: 600 }}>{'▶'} Tracing</span>
              <select
                value={traceId ?? ''}
                onChange={(e) => pickScenario(e.target.value)}
                style={{
                  background: 'var(--s2)', border: '1px solid var(--b3)', borderRadius: 'var(--r)',
                  padding: '4px 8px', fontFamily: 'var(--font-mono)', fontSize: 10,
                  color: 'var(--tx)', outline: 'none', cursor: 'pointer',
                }}
              >
                <option value="">— pick a scenario —</option>
                <option value="withdraw">Player withdraws £500</option>
                <option value="deposit">Player deposits via card</option>
                <option value="register">New player registration</option>
                <option value="play">Player initiates game round</option>
              </select>
              <div style={{ flex: 1, fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--t2)', display: 'flex', alignItems: 'center', gap: 4, flexWrap: 'wrap' }}>
                {sc ? sc.steps.map((step, i) => (
                  <span key={step.id} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    {i > 0 && <span style={{ color: 'var(--t4)' }}>{'→'}</span>}
                    <span style={{ padding: '2px 7px', background: 'var(--ywb)', border: '1px solid var(--ywbd)', borderRadius: 3, color: traceGaps.has(step.id) ? 'var(--rd)' : 'var(--yw)', cursor: 'pointer' }}>
                      {step.id}
                    </span>
                  </span>
                )) : <span style={{ color: 'var(--t4)', fontSize: 10 }}>Select a scenario above</span>}
              </div>
              {sc && (
                <span style={{ fontSize: 10, color: 'var(--t3)', fontFamily: 'var(--font-mono)' }}>
                  {sc.steps.length} steps · {gaps} gap{gaps !== 1 ? 's' : ''}
                </span>
              )}
            </>
          )}

          {lens === 'auth' && (
            <>
              <span style={{ fontSize: 11, color: 'var(--rd)', fontWeight: 600 }}>Authorization</span>
              <span style={{ flex: 1, fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--t2)' }}>
                Actor / action policy matrix. Click a resource to view authorization details.
              </span>
            </>
          )}

          {lens === 'cfg' && (
            <>
              <span style={{ fontSize: 11, color: 'var(--pu)', fontWeight: 600 }}>Config view</span>
              <span style={{ flex: 1, fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--t2)' }}>
                Schema / ERD. Click any resource to view field schema.
              </span>
            </>
          )}

          <button
            onClick={clearTrace}
            style={{ background: 'none', border: 'none', color: 'var(--t3)', cursor: 'pointer', fontSize: 13, padding: 2 }}
          >
            ✕
          </button>
        </div>
      )}
    </div>
  );
}
