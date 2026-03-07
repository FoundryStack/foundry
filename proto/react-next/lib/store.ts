'use client';

import { create } from 'zustand';
import type { AppState, Lens, FeedCard } from './types';
import { EDGES, NODES, SCENARIOS, INITIAL_FEED } from './data';

type Actions = {
  selectNode: (id: string | null) => void;
  setLens: (lens: Lens) => void;
  pickScenario: (id: string) => void;
  clearTrace: () => void;
  setDrawerTab: (tab: AppState['drawerTab']) => void;
  openDrawer: (id: string) => void;
  closeDrawer: () => void;
  toggleFeed: () => void;
  setFeedTab: (tab: AppState['feedTab']) => void;
  openPalette: () => void;
  closePalette: () => void;
  openBottomSheet: (nodeId: string) => void;
  closeBottomSheet: () => void;
  setBsTab: (tab: AppState['bsTab']) => void;
  setBsAdr: (adr: string) => void;
  submitProposal: () => void;
  showToast: (msg: string) => void;
  dismissToast: () => void;
  addFeedCard: (card: Omit<FeedCard, 'id'>) => void;
  feedCards: FeedCard[];
};

type Store = AppState & Actions;

let _feedCounter = INITIAL_FEED.length + 1;

function nextId() {
  return `fc-${_feedCounter++}`;
}

function computeImpactSet(nodeId: string): Set<string> {
  const set = new Set<string>();
  EDGES.forEach((e) => {
    if (e.f === nodeId) set.add(e.t);
    if (e.t === nodeId) set.add(e.f);
  });
  return set;
}

export const useStore = create<Store>((set, get) => ({
  // ── State ──────────────────────────────────────────────────────────────────
  selectedId: null,
  lens: 'str',
  traceId: null,
  traceSet: new Set(),
  traceGaps: new Set(),
  impNode: null,
  impSet: new Set(),
  drawerTab: 'details',
  drawerOpen: false,
  feedOpen: true,
  feedTab: 'feed',
  paletteOpen: false,
  bsOpen: false,
  bsNodeId: null,
  bsTab: 'diff',
  bsAdr: '',
  toastMessage: null,
  feedCards: INITIAL_FEED,

  // ── Actions ────────────────────────────────────────────────────────────────

  selectNode: (id) => {
    const { lens } = get();
    let impNode: string | null = null;
    let impSet = new Set<string>();

    if (id && lens === 'imp') {
      impNode = id;
      impSet = computeImpactSet(id);
    }

    set({ selectedId: id, impNode, impSet });

    if (id) {
      get().openDrawer(id);
    } else {
      set({ drawerOpen: false });
    }
  },

  setLens: (lens) => {
    const { selectedId } = get();
    let impNode: string | null = null;
    let impSet = new Set<string>();
    let traceId: string | null = null;
    let traceSet = new Set<string>();
    let traceGaps = new Set<string>();

    if (lens === 'imp' && selectedId) {
      impNode = selectedId;
      impSet = computeImpactSet(selectedId);
    }

    if (lens !== 'trc') {
      traceId = null;
      traceSet = new Set();
      traceGaps = new Set();
    } else {
      traceId = get().traceId;
      traceSet = get().traceSet;
      traceGaps = get().traceGaps;
    }

    set({ lens, impNode, impSet, traceId, traceSet, traceGaps });
  },

  pickScenario: (id) => {
    if (!id) {
      set({ traceId: null, traceSet: new Set(), traceGaps: new Set() });
      return;
    }

    const sc = SCENARIOS[id];
    if (!sc) return;

    const traceSet = new Set<string>();
    const traceGaps = new Set<string>();
    sc.steps.forEach((s) => {
      traceSet.add(s.id);
      if (s.gap) traceGaps.add(s.id);
    });

    set({ traceId: id, traceSet, traceGaps, lens: 'trc' });
  },

  clearTrace: () => {
    set({
      traceId: null,
      traceSet: new Set(),
      traceGaps: new Set(),
      lens: 'str',
      impNode: null,
      impSet: new Set(),
    });
  },

  setDrawerTab: (drawerTab) => set({ drawerTab }),

  openDrawer: (id) => {
    set({ drawerOpen: true, selectedId: id });
  },

  closeDrawer: () => {
    set({ drawerOpen: false, selectedId: null });
  },

  toggleFeed: () => set((s) => ({ feedOpen: !s.feedOpen })),

  setFeedTab: (feedTab) => set({ feedTab }),

  openPalette: () => set({ paletteOpen: true }),

  closePalette: () => set({ paletteOpen: false }),

  openBottomSheet: (nodeId) =>
    set({ bsOpen: true, bsNodeId: nodeId, bsTab: 'diff', bsAdr: '' }),

  closeBottomSheet: () => set({ bsOpen: false }),

  setBsTab: (bsTab) => set({ bsTab }),

  setBsAdr: (bsAdr) => set({ bsAdr }),

  submitProposal: () => {
    const { bsNodeId } = get();
    const node = bsNodeId ? NODES[bsNodeId] : null;
    get().closeBottomSheet();
    if (node) {
      get().addFeedCard({
        type: 'proposal',
        time: 'just now',
        body: `Proposal for <strong>${node.name}</strong> submitted. Awaiting compliance officer approval.`,
      });
      get().showToast('Proposal submitted · Compliance Officer notified');
    }
  },

  showToast: (msg) => {
    set({ toastMessage: msg });
    setTimeout(() => set({ toastMessage: null }), 2800);
  },

  dismissToast: () => set({ toastMessage: null }),

  addFeedCard: (card) =>
    set((s) => ({
      feedCards: [{ ...card, id: nextId() }, ...s.feedCards],
    })),
}));
