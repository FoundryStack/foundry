'use client';

import { useStore } from '@/lib/store';
import DrawerDetails from './drawer/DrawerDetails';
import DrawerFlow from './drawer/DrawerFlow';
import DrawerActions from './drawer/DrawerActions';

const TABS = [
  { id: 'details',   label: 'Details'  },
  { id: 'flow',      label: 'Flow'     },
  { id: 'shortcuts', label: 'Actions'  },
] as const;

export default function Drawer() {
  const drawerOpen = useStore((s) => s.drawerOpen);
  const drawerTab  = useStore((s) => s.drawerTab);
  const setDrawerTab = useStore((s) => s.setDrawerTab);
  const closeDrawer  = useStore((s) => s.closeDrawer);

  return (
    <div
      style={{
        width: drawerOpen ? 360 : 0,
        minWidth: drawerOpen ? 360 : 0,
        background: 'var(--s1)',
        borderRight: '1px solid var(--b1)',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
        transition: 'width .2s, min-width .2s',
        flexShrink: 0,
      }}
    >
      {/* Tab bar */}
      <div style={{ display: 'flex', borderBottom: '1px solid var(--b1)', flexShrink: 0 }}>
        {TABS.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setDrawerTab(tab.id)}
            style={{
              flex: 1, padding: '8px 0', textAlign: 'center',
              fontSize: 11, fontWeight: 500, cursor: 'pointer',
              background: 'none', border: 'none',
              borderBottom: `2px solid ${drawerTab === tab.id ? 'var(--ac)' : 'transparent'}`,
              color: drawerTab === tab.id ? 'var(--tx)' : 'var(--t3)',
              transition: '.1s',
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Close row */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '8px 12px 0', flexShrink: 0 }}>
        <button
          onClick={closeDrawer}
          style={{
            background: 'none', border: 'none', color: 'var(--t3)',
            cursor: 'pointer', fontSize: 12, padding: '3px 6px',
            borderRadius: 3, transition: '.1s',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'var(--s3)';
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--t2)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'none';
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--t3)';
          }}
        >
          ✕ close
        </button>
      </div>

      {/* Content — flex column fills remaining height */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {drawerTab === 'details'   && <DrawerDetails />}
        {drawerTab === 'flow'      && <DrawerFlow />}
        {drawerTab === 'shortcuts' && <DrawerActions />}
      </div>
    </div>
  );
}
