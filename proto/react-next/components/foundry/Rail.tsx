'use client';

import { Hexagon, Scale, Zap, Star, Settings } from 'lucide-react';
import { useStore } from '@/lib/store';
import { cn } from '@/lib/utils';

type RailButton = {
  icon: React.ReactNode;
  label: string;
  active?: boolean;
  onClick: () => void;
};

function RailBtn({ icon, label, active, onClick }: RailButton) {
  return (
    <button
      onClick={onClick}
      title={label}
      className={cn('r-btn', active && 'r-btn-active')}
      style={{
        width: 34, height: 34, borderRadius: 'var(--r)', border: 'none',
        background: active ? 'var(--acb)' : 'none',
        color: active ? 'var(--ac2)' : 'var(--t3)',
        cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 16, transition: '.1s', position: 'relative',
      }}
      onMouseEnter={(e) => {
        if (!active) {
          (e.currentTarget as HTMLButtonElement).style.background = 'var(--s3)';
          (e.currentTarget as HTMLButtonElement).style.color = 'var(--t2)';
        }
      }}
      onMouseLeave={(e) => {
        if (!active) {
          (e.currentTarget as HTMLButtonElement).style.background = 'none';
          (e.currentTarget as HTMLButtonElement).style.color = 'var(--t3)';
        }
      }}
    >
      {icon}
      {/* Tooltip */}
      <span
        className="rail-tip"
        style={{
          position: 'absolute', left: 'calc(100% + 8px)', top: '50%', transform: 'translateY(-50%)',
          background: 'var(--s4)', border: '1px solid var(--b3)', borderRadius: 'var(--r)',
          padding: '4px 9px', fontSize: 11, color: 'var(--tx)', whiteSpace: 'nowrap',
          pointerEvents: 'none', zIndex: 300,
          opacity: 0, transition: 'opacity .1s',
        }}
      >
        {label}
      </span>
    </button>
  );
}

export default function Rail() {
  const activePanel = useStore((s) => s.activePanel);
  const setActivePanel = useStore((s) => s.setActivePanel);
  const showToast = useStore((s) => s.showToast);

  return (
    <nav
      style={{
        width: 46, minWidth: 46, background: 'var(--s1)', borderRight: '1px solid var(--b1)',
        display: 'flex', flexDirection: 'column', alignItems: 'center',
        padding: '8px 0', gap: 2, flexShrink: 0,
      }}
    >
      <style>{`.r-btn:hover .rail-tip { opacity: 1 !important; }`}</style>

      <RailBtn icon={<Hexagon size={16} />} label="System Map" active={activePanel === 'system-map'} onClick={() => setActivePanel('system-map')} />
      <RailBtn icon={<Scale size={16} />} label="Compliance" active={activePanel === 'compliance'} onClick={() => setActivePanel('compliance')} />
      <RailBtn icon={<Zap size={16} />} label="Operations" active={activePanel === 'operations'} onClick={() => setActivePanel('operations')} />
      <RailBtn icon={<Star size={14} />} label="Test Coverage" active={activePanel === 'test-coverage'} onClick={() => setActivePanel('test-coverage')} />

      <div style={{ flex: 1 }} />

      <RailBtn icon={<Settings size={15} />} label="Settings" onClick={() => showToast('Settings')} />
    </nav>
  );
}
