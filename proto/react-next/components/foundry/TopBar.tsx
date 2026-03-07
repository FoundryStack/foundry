'use client';

import { Bell, AlignRight } from 'lucide-react';
import { useStore } from '@/lib/store';

export default function TopBar() {
  const openPalette = useStore((s) => s.openPalette);
  const toggleFeed = useStore((s) => s.toggleFeed);
  const showToast = useStore((s) => s.showToast);

  return (
    <header
      style={{
        height: 40,
        minHeight: 40,
        background: 'var(--s1)',
        borderBottom: '1px solid var(--b1)',
        display: 'flex',
        alignItems: 'center',
        padding: '0 12px',
        gap: 10,
        zIndex: 200,
        userSelect: 'none',
        flexShrink: 0,
      }}
    >
      {/* Logo */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontFamily: 'var(--font-mono)', fontSize: 11, fontWeight: 500, letterSpacing: '.12em', color: 'var(--ac2)' }}>
        <div style={{ width: 24, height: 24, background: 'linear-gradient(135deg,#5b4cf0,#7c6dfa)', borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 700, color: '#fff' }}>
          F
        </div>
        FOUNDRY
      </div>

      <div style={{ width: 1, height: 16, background: 'var(--b2)' }} />

      {/* Breadcrumb */}
      <div style={{ fontSize: 12, color: 'var(--t2)', display: 'flex', alignItems: 'center', gap: 6 }}>
        <strong style={{ color: 'var(--tx)', fontWeight: 500 }}>igaming-platform</strong>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, padding: '2px 6px', borderRadius: 3, background: 'var(--gnb)', color: 'var(--gn)', border: '1px solid var(--gnbd)' }}>local</span>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, padding: '2px 6px', borderRadius: 3, background: 'var(--acb)', color: 'var(--ac2)', border: '1px solid var(--acbd)' }}>Phase 2</span>
      </div>

      <div style={{ width: 1, height: 16, background: 'var(--b2)' }} />

      <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--t3)' }}>
        synced <span style={{ color: 'var(--t2)' }}>18s ago</span>
      </div>

      <div style={{ flex: 1 }} />

      {/* Command palette trigger */}
      <button
        onClick={openPalette}
        style={{
          fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--t3)',
          background: 'var(--s2)', border: '1px solid var(--b2)', borderRadius: 'var(--r)',
          padding: '4px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6,
          transition: '.12s',
        }}
        onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--t2)'; (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b3)'; }}
        onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--t3)'; (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b2)'; }}
      >
        Jump to…{' '}
        <kbd style={{ fontFamily: 'var(--font-mono)', fontSize: 10, background: 'var(--s3)', border: '1px solid var(--b3)', borderRadius: 3, padding: '1px 5px', color: 'var(--t3)' }}>⌘K</kbd>
      </button>

      {/* Feed toggle */}
      <button
        onClick={toggleFeed}
        title="Toggle Activity Feed"
        style={{ width: 30, height: 30, background: 'none', border: '1px solid var(--b2)', borderRadius: 'var(--r)', color: 'var(--t2)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', transition: '.12s' }}
        onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'var(--s2)'; (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b3)'; (e.currentTarget as HTMLButtonElement).style.color = 'var(--tx)'; }}
        onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'none'; (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b2)'; (e.currentTarget as HTMLButtonElement).style.color = 'var(--t2)'; }}
      >
        <AlignRight size={15} />
      </button>

      {/* Notifications */}
      <button
        onClick={() => showToast('2 proposals pending')}
        title="Notifications"
        style={{ width: 30, height: 30, background: 'none', border: '1px solid var(--b2)', borderRadius: 'var(--r)', color: 'var(--t2)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative', transition: '.12s' }}
        onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'var(--s2)'; (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b3)'; (e.currentTarget as HTMLButtonElement).style.color = 'var(--tx)'; }}
        onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'none'; (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b2)'; (e.currentTarget as HTMLButtonElement).style.color = 'var(--t2)'; }}
      >
        <Bell size={14} />
        <span style={{ position: 'absolute', top: 4, right: 4, width: 5, height: 5, borderRadius: '50%', background: 'var(--rd)', border: '1.5px solid var(--s1)' }} />
      </button>
    </header>
  );
}
