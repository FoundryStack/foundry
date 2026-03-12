'use client';

import { useStore } from '@/lib/store';
import { NODES } from '@/lib/data';
import type { NodeType } from '@/lib/types';

type Shortcut = { label: string; intent: string };

const SHORTCUTS_BY_TYPE: Partial<Record<NodeType, Shortcut[]>> = {
  resource: [
    { label: 'Add attribute', intent: `Add a new attribute to this resource` },
    { label: 'Add action', intent: `Add a new action to this resource` },
    { label: 'Add policy', intent: `Add a policy to this resource` },
    { label: 'Generate tests', intent: `Generate property and scenario tests for this resource` },
    { label: 'Link compliance requirement', intent: `Link a compliance requirement to this resource` },
  ],
  transfer: [
    { label: 'Add rule', intent: `Add a rule to guard steps in this transfer` },
    { label: 'Add step', intent: `Add a step to this transfer` },
    { label: 'Generate tests', intent: `Generate scenario tests for this transfer` },
    { label: 'View runbook', intent: `Show runbook for this transfer` },
  ],
  reactor: [
    { label: 'Add rule', intent: `Add a rule to guard steps in this reactor` },
    { label: 'Add step', intent: `Add a step to this reactor` },
    { label: 'Generate tests', intent: `Generate scenario tests for this reactor` },
    { label: 'View runbook', intent: `Show runbook for this reactor` },
  ],
  rule: [
    { label: 'Add jurisdiction clause', intent: `Add a jurisdiction clause to this rule` },
    { label: 'Generate tests', intent: `Generate tests for this rule` },
    { label: 'Link compliance requirement', intent: `Link a compliance requirement to this rule` },
  ],
  blueprint: [
    { label: 'Add eligibility clause', intent: `Add an eligibility clause to this blueprint` },
    { label: 'Generate tests', intent: `Generate tests for this blueprint` },
  ],
};

// Oban worker: reactor with oban queue
const OBAN_SHORTCUTS: Shortcut[] = [
  { label: 'Generate tests', intent: `Generate tests for this Oban worker` },
  { label: 'View runbook', intent: `Show runbook for this worker` },
];

const DEFAULT_SHORTCUTS: Shortcut[] = [
  { label: 'Generate tests', intent: `Generate tests for this module` },
  { label: 'View runbook', intent: `Show runbook` },
];

function getShortcuts(nodeType: NodeType, oban: string[]): Shortcut[] {
  if (oban.length > 0) return OBAN_SHORTCUTS;
  return SHORTCUTS_BY_TYPE[nodeType] ?? DEFAULT_SHORTCUTS;
}

const BTN_P: React.CSSProperties = {
  display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5,
  padding: '8px 12px', background: 'var(--ac)', border: 'none', borderRadius: 'var(--r)',
  fontFamily: 'var(--font-sans)', fontSize: 12, fontWeight: 500, color: '#fff',
  cursor: 'pointer', width: '100%', transition: '.12s',
};

export default function DrawerActions() {
  const selectedId     = useStore((s) => s.selectedId);
  const openBottomSheet = useStore((s) => s.openBottomSheet);
  const setFeedIntent  = useStore((s) => s.setFeedIntent);

  const n = selectedId ? NODES[selectedId] : null;
  if (!n) return null;

  const shortcuts = getShortcuts(n.type, n.oban ?? []);

  function handleShortcut(intent: string) {
    setFeedIntent(intent);
  }

  return (
    <>
      <div style={{ flex: 1, overflowY: 'auto' }}>
        <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--b1)' }}>
          <div style={{
            fontSize: 9, fontWeight: 600, letterSpacing: '.12em',
            textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 9,
          }}>
            Contextual Intent Shortcuts
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            {shortcuts.map((s) => (
              <button
                key={s.label}
                onClick={() => handleShortcut(s.intent)}
                style={{
                  background: 'var(--s2)', border: '1px solid var(--b2)', borderRadius: 5,
                  padding: '8px 10px', fontSize: 11, color: 'var(--t2)',
                  cursor: 'pointer', textAlign: 'left', transition: '.1s', lineHeight: 1.4,
                }}
                onMouseEnter={(e) => {
                  (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b3)';
                  (e.currentTarget as HTMLButtonElement).style.color = 'var(--tx)';
                }}
                onMouseLeave={(e) => {
                  (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--b2)';
                  (e.currentTarget as HTMLButtonElement).style.color = 'var(--t2)';
                }}
              >
                {s.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div style={{ padding: '10px 14px 14px', borderTop: '1px solid var(--b1)', flexShrink: 0 }}>
        <button style={BTN_P} onClick={() => openBottomSheet(n.id)}>
          Open proposal panel
        </button>
      </div>
    </>
  );
}
