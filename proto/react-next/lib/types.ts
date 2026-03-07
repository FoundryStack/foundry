// ─── Core node types ──────────────────────────────────────────────────────────

export type NodeType = 'resource' | 'transfer' | 'rule' | 'reactor';

export type TestSuite = {
  p: boolean; // property tests
  s: boolean; // scenario tests
  e: boolean; // e2e tests
};

export type StateMachineTransition = {
  f: string;
  t: string;
  ev: string;
};

export type StateMachine = {
  on: boolean;
  states: string[];
  tr: StateMachineTransition[];
  attr: string | null;
};

export type Attribute = {
  n: string;
  t: string;
  d: string;
  pii: boolean;
  mon: boolean;
  sen: boolean;
};

export type Action = {
  n: string;
  c: string;
};

export type MoneyField = {
  n: string;
  t: string;
  cldr: string;
};

export type Route = {
  r: string;
  m: string;
  auth: boolean;
};

export type FeatureFlag = {
  n: string;
  adr?: string;
};

export type GraphNode = {
  id: string;
  name: string;
  type: NodeType;
  domain: string;
  module: string;
  sensitive: boolean;
  gap: boolean;
  cov: number;
  desc: string;
  attrs: Attribute[];
  actions: Action[];
  reqs: string[];
  adrs: string[];
  runbook: string | null;
  tests: TestSuite;
  dl: string | null;
  pt: boolean;
  arch: boolean;
  pm: boolean;
  sm: StateMachine;
  routes: Route[];
  telem: string[];
  money: MoneyField[];
  auth: boolean;
  oban: string[];
  rl: boolean;
  flags: FeatureFlag[];
  mod: string;
};

// ─── Graph edge ───────────────────────────────────────────────────────────────

export type EdgeRelation = 'calls' | 'enforces' | 'triggers' | 'references';

export type GraphEdge = {
  f: string;
  t: string;
  r: EdgeRelation;
};

// ─── Lens ─────────────────────────────────────────────────────────────────────

export type Lens = 'str' | 'cmp' | 'sen' | 'hlth' | 'trc' | 'imp' | 'erd';

// ─── Scenario trace ───────────────────────────────────────────────────────────

export type ScenarioStep = {
  id: string;
  action: string;
  note: string;
  reqs: string[];
  gap: boolean;
  gapNote?: string;
};

export type Scenario = {
  label: string;
  steps: ScenarioStep[];
};

// ─── Feed card ────────────────────────────────────────────────────────────────

export type FeedCardType = 'question' | 'response' | 'proposal' | 'error' | 'ci';

export type FeedCard = {
  id: string;
  type: FeedCardType;
  time: string;
  body: string;
  conf?: 'HIGH' | 'MEDIUM' | 'LOW';
};

// ─── App state ────────────────────────────────────────────────────────────────

export type AppState = {
  selectedId: string | null;
  lens: Lens;
  traceId: string | null;
  traceSet: Set<string>;
  traceGaps: Set<string>;
  impNode: string | null;
  impSet: Set<string>;
  drawerTab: 'details' | 'flow' | 'shortcuts';
  drawerOpen: boolean;
  feedOpen: boolean;
  feedTab: 'feed' | 'copilot';
  paletteOpen: boolean;
  bsOpen: boolean;
  bsNodeId: string | null;
  bsTab: 'diff' | 'lint' | 'impact' | 'approval';
  bsAdr: string;
  toastMessage: string | null;
};
