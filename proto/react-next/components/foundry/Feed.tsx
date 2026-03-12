'use client';

import { useRef, useEffect, KeyboardEvent } from 'react';
import { useStore } from '@/lib/store';
import type { FeedCard } from '@/lib/types';

// ─── Card colors ─────────────────────────────────────────────────────────────

const CARD_BORDER: Record<string, string> = {
  question: 'var(--ac)',
  response: 'var(--t4)',
  proposal: 'var(--yw)',
  error:    'var(--rd)',
  ci:       'var(--gn)',
};

const WHO: Record<string, string> = {
  question: 'You',
  response: 'Copilot',
  proposal: 'Proposal',
  error:    'System',
  ci:       'CI',
};

const CONF_STYLE: Record<string, React.CSSProperties> = {
  HIGH:   { background: 'var(--gnb)',  color: 'var(--gn)',  border: '1px solid var(--gnbd)'  },
  MEDIUM: { background: 'var(--ywb)',  color: 'var(--yw)',  border: '1px solid var(--ywbd)'  },
  LOW:    { background: 'var(--rdb)',  color: 'var(--rd)',  border: '1px solid var(--rdbd)'  },
};

// ─── Single feed card ─────────────────────────────────────────────────────────

function FeedCardItem({ card, onReview }: { card: FeedCard; onReview: () => void }) {
  return (
    <div style={{
      background: 'var(--s2)', border: '1px solid var(--b1)',
      borderLeft: `2px solid ${CARD_BORDER[card.type] ?? 'var(--t4)'}`,
      borderRadius: 6, padding: '9px 11px', fontSize: 11,
      ...(card.type === 'proposal' ? { background: 'rgba(245,158,11,.03)' } : {}),
    }}>
      {/* Top row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 4 }}>
        <span style={{ fontWeight: 600, color: 'var(--t2)', fontSize: 10 }}>
          {WHO[card.type] ?? card.type}
        </span>
        {card.conf && (
          <span style={{
            fontFamily: 'var(--font-mono)', fontSize: 8, padding: '1px 4px',
            borderRadius: 2, ...CONF_STYLE[card.conf],
          }}>
            {card.conf}
          </span>
        )}
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', marginLeft: 'auto' }}>
          {card.time}
        </span>
      </div>

      {/* Body — allow HTML from the original data */}
      <div
        style={{ color: 'var(--t2)', lineHeight: 1.55 }}
        dangerouslySetInnerHTML={{ __html: card.body }}
      />

      {/* Review button for proposals */}
      {card.type === 'proposal' && (
        <div style={{ marginTop: 7, display: 'flex', gap: 5 }}>
          <button
            onClick={onReview}
            style={{
              fontSize: 10, padding: '3px 9px', border: '1px solid var(--acbd)',
              background: 'var(--acb)', borderRadius: 4, color: 'var(--ac2)',
              cursor: 'pointer', transition: '.1s',
            }}
          >
            Review →
          </button>
        </div>
      )}
    </div>
  );
}

// ─── Feed panel ───────────────────────────────────────────────────────────────

export default function Feed() {
  const feedOpen     = useStore((s) => s.feedOpen);
  const feedTab      = useStore((s) => s.feedTab);
  const feedCards    = useStore((s) => s.feedCards);
  const feedIntent   = useStore((s) => s.feedIntent);
  const clearFeedIntent = useStore((s) => s.clearFeedIntent);
  const toggleFeed  = useStore((s) => s.toggleFeed);
  const setFeedTab   = useStore((s) => s.setFeedTab);
  const addFeedCard  = useStore((s) => s.addFeedCard);
  const showToast    = useStore((s) => s.showToast);
  const inputRef     = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (feedIntent && inputRef.current) {
      inputRef.current.value = feedIntent;
      inputRef.current.focus();
      clearFeedIntent();
    }
  }, [feedIntent, clearFeedIntent]);

  function handleChat(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      const v = e.currentTarget.value.trim();
      if (!v) return;
      addFeedCard({ type: 'question', time: 'just now', body: v });
      e.currentTarget.value = '';
      setTimeout(() => {
        addFeedCard({
          type: 'response', time: 'just now', conf: 'HIGH',
          body: 'Processing your request against the current project context…',
        });
      }, 600);
    }
  }

  return (
    <div
      style={{
        width: feedOpen ? 320 : 0,
        minWidth: feedOpen ? 320 : 0,
        background: 'var(--s1)',
        borderLeft: '1px solid var(--b1)',
        display: 'flex', flexDirection: 'column',
        overflow: 'hidden',
        transition: 'width .2s, min-width .2s',
        flexShrink: 0,
      }}
    >
      {/* Header */}
      <div style={{
        padding: '8px 12px', borderBottom: '1px solid var(--b1)',
        display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0,
      }}>
        <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--tx)', flex: 1 }}>Activity</div>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t4)' }}>⌘\</span>
        <button
          onClick={toggleFeed}
          style={{ background: 'none', border: 'none', color: 'var(--t3)', cursor: 'pointer', fontSize: 13, padding: 3, borderRadius: 3, transition: '.1s' }}
          onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--t2)'; (e.currentTarget as HTMLButtonElement).style.background = 'var(--s2)'; }}
          onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--t3)'; (e.currentTarget as HTMLButtonElement).style.background = 'none'; }}
        >
          &#x27E9;
        </button>
      </div>

      {/* Tabs */}
      <div style={{ display: 'flex', borderBottom: '1px solid var(--b1)', flexShrink: 0 }}>
        {(['feed', 'copilot'] as const).map((t) => (
          <button
            key={t}
            onClick={() => setFeedTab(t)}
            style={{
              flex: 1, padding: '6px 0', textAlign: 'center',
              fontSize: 10, fontWeight: 500, cursor: 'pointer',
              background: 'none', border: 'none',
              borderBottom: `2px solid ${feedTab === t ? 'var(--ac)' : 'transparent'}`,
              color: feedTab === t ? 'var(--tx)' : 'var(--t3)',
              transition: '.1s', textTransform: 'capitalize',
            }}
          >
            {t === 'feed' ? 'Feed' : 'Copilot'}
          </button>
        ))}
      </div>

      {/* Stream */}
      <div style={{ flex: 1, overflowY: 'auto', padding: 8, display: 'flex', flexDirection: 'column', gap: 5 }}>
        {feedCards.map((card) => (
          <FeedCardItem
            key={card.id}
            card={card}
            onReview={() => showToast('Opening proposal…')}
          />
        ))}
      </div>

      {/* Input */}
      <div style={{ padding: 8, borderTop: '1px solid var(--b1)', flexShrink: 0 }}>
        <textarea
          ref={inputRef}
          rows={2}
          placeholder="Ask a question or describe a change…"
          onKeyDown={handleChat}
          style={{
            width: '100%', background: 'var(--s2)', border: '1px solid var(--b2)',
            borderRadius: 'var(--r)', padding: '7px 10px',
            fontFamily: 'var(--font-sans)', fontSize: 11, color: 'var(--tx)',
            outline: 'none', resize: 'none', transition: '.12s', lineHeight: 1.5,
          }}
          onFocus={(e) => (e.currentTarget.style.borderColor = 'var(--ac)')}
          onBlur={(e) => (e.currentTarget.style.borderColor = 'var(--b2)')}
        />
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t4)', textAlign: 'right', marginTop: 4 }}>
          ⏎ send · ⇧⏎ newline
        </div>
      </div>
    </div>
  );
}
