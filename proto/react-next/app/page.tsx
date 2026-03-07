'use client';

import { useEffect } from 'react';
import { useStore } from '@/lib/store';

import TopBar         from '@/components/foundry/TopBar';
import Rail           from '@/components/foundry/Rail';
import Sidebar        from '@/components/foundry/Sidebar';
import LensBar        from '@/components/foundry/LensBar';
import Canvas         from '@/components/foundry/Canvas';
import Drawer         from '@/components/foundry/Drawer';
import Feed           from '@/components/foundry/Feed';
import CommandPalette from '@/components/foundry/CommandPalette';
import BottomSheet    from '@/components/foundry/BottomSheet';

export default function FoundryPage() {
  const openPalette  = useStore((s) => s.openPalette);
  const toastMessage = useStore((s) => s.toastMessage);
  const dismissToast = useStore((s) => s.dismissToast);

  // Global ⌘K shortcut
  useEffect(() => {
    function handler(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        openPalette();
      }
    }
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [openPalette]);

  return (
    <div
      style={{
        display: 'flex', flexDirection: 'column',
        height: '100vh', width: '100vw', overflow: 'hidden',
        background: 'var(--bg)', color: 'var(--tx)',
        fontFamily: 'var(--font-sans, Geist, sans-serif)',
      }}
    >
      {/* ── Top bar ───────────────────────────────────────────────────────── */}
      <TopBar />

      {/* ── Main workspace ────────────────────────────────────────────────── */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden', minHeight: 0 }}>
        {/* Left rail */}
        <Rail />

        {/* Sidebar: domain / module list */}
        <Sidebar />

        {/* Central column: lens bar + canvas + drawer */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden', minWidth: 0 }}>
          {/* Lens bar + trace context bar */}
          <LensBar />

          {/* Canvas row */}
          <div style={{ flex: 1, display: 'flex', overflow: 'hidden', minHeight: 0 }}>
            {/* Graph canvas */}
            <Canvas />

            {/* Detail drawer (left-panel style, slides in from right of canvas) */}
            <Drawer />
          </div>
        </div>

        {/* Right feed panel */}
        <Feed />
      </div>

      {/* ── Overlays ──────────────────────────────────────────────────────── */}
      <CommandPalette />
      <BottomSheet />

      {/* ── Toast ─────────────────────────────────────────────────────────── */}
      {toastMessage && (
        <div
          role="alert"
          aria-live="polite"
          onClick={dismissToast}
          style={{
            position: 'fixed', bottom: 24, left: '50%', transform: 'translateX(-50%)',
            background: 'var(--s4)', border: '1px solid var(--b3)', borderRadius: 8,
            padding: '10px 20px', fontSize: 12, color: 'var(--tx)',
            boxShadow: '0 8px 32px rgba(0,0,0,.6)', zIndex: 600,
            pointerEvents: 'all', cursor: 'pointer', whiteSpace: 'nowrap',
            animation: 'fadeUp .18s ease forwards',
          }}
        >
          {toastMessage}
        </div>
      )}

      <style>{`
        @keyframes fadeUp {
          from { opacity: 0; transform: translateX(-50%) translateY(8px); }
          to   { opacity: 1; transform: translateX(-50%) translateY(0);   }
        }
      `}</style>
    </div>
  );
}
