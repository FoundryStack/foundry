'use client';

import { useState, useEffect } from 'react';

/**
 * Returns false for `delayMs`, then true. Use for loading states per ADR-012:
 * "Loading states appear after a 200ms delay. Below 200ms, no loading indicator is shown."
 * For demo: we show loading for 200ms then content. In production, content would
 * arrive async and we'd show loading only if it takes > 200ms.
 */
export function useDelayedReady(delayMs = 200): boolean {
  const [ready, setReady] = useState(delayMs === 0);

  useEffect(() => {
    if (delayMs <= 0) {
      setReady(true);
      return;
    }
    const t = setTimeout(() => setReady(true), delayMs);
    return () => clearTimeout(t);
  }, [delayMs]);

  return ready;
}
