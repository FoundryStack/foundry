// ─── Node types (per spec section 3) ──────────────────────────────────────────

export type NodeType =
  | 'resource'      // ⬡ Ash.Resource
  | 'transfer'      // ⇄ Transfer / Saga
  | 'rule'          // ◈ Rule / Policy
  | 'reactor'       // ⚡ Reactor / ObanJob
  | 'input'         // ▶ Input (trigger) — API route / Webhook / Scheduler
  | 'output'        // ⟐ Output (terminal) — Success / Error / Compensation
  | 'blueprint'     // ◇ Campaign/bonus configuration template
  | 'liveresource'  // ▣ Back-office UI page (ash_live_resource)
  | 'provider';     // ⬚ Provider Adapter — external system boundary

// ─── FSM state markers (per spec section 3) ───────────────────────────────────

export type FsmStateMarker = 'normal' | 'active' | 'trap'; // ◦ • ⊗

export type FsmState = {
  id: string;
  name: string;
  marker: FsmStateMarker;
};

export type StateMachineTransition = {
  f: string;       // from state
  t: string;       // to state
  ev: string;      // event name
  guard?: string;  // optional guard rule id
};

export type StateMachine = {
  on: boolean;
  states: FsmState[];
  tr: StateMachineTransition[];
  attr: string | null;
};

// ─── Test suite ───────────────────────────────────────────────────────────────

export type TestSuite = {
  p: boolean;  // property tests
  s: boolean;  // scenario tests
  e: boolean;  // e2e tests
};

// ─── Status indicators (per spec section 5) ───────────────────────────────────

export type CompliancePosture = 'covered' | 'gap' | 'missing';
export type TestCoverageBand = 'green' | 'amber' | 'red'; // >=80%, 50-79%, <50%

export type StatusIndicators = {
  compliance: CompliancePosture;       // ⬡
  testCoverage: TestCoverageBand;      // ◉
  propTests: boolean;                  // P
  scenarioTests: boolean;              // S
  e2eTests: boolean;                   // E
  adrLinked: boolean;                  // ~
  runbook: 'exists' | 'stale' | 'missing'; // 📖
  pendingMigration: boolean;           // ⚠
  sensitive: boolean;                  // ▒
  paperTrail: boolean;                 // ⊕
  archival: boolean;                   // ⊘
  rateLimited: boolean;                // ↻
  telemetry: boolean;                  // ○
  featureFlagGating: 'compliance' | 'other' | null; // ⚙
};

// ─── Attribute ────────────────────────────────────────────────────────────────

export type Attribute = {
  n: string;
  t: string;
  d: string;
  pii: boolean;
  mon: boolean;
  sen: boolean;
};

// ─── Action ───────────────────────────────────────────────────────────────────

export type Action = {
  n: string;
  c: string; // change class: sensitive | compliance | behavioral | structural
};

// ─── Money field ──────────────────────────────────────────────────────────────

export type MoneyField = {
  n: string;
  t: string;
  cldr: string;
};

// ─── Route ────────────────────────────────────────────────────────────────────

export type Route = {
  r: string;
  m: string;
  auth: boolean;
  rl?: boolean;       // rate limited
  idem?: boolean;     // idempotency key mechanism
};

// ─── Feature flag ─────────────────────────────────────────────────────────────

export type FeatureFlag = {
  n: string;
  adr?: string;
  type?: 'compliance' | 'other';
};

// ─── Transfer step (per spec section 11) ──────────────────────────────────────

export type TransferStep = {
  id: string;
  name: string;
  reads: string[];    // resource IDs this step reads
  writes: string[];   // resource IDs this step writes
  reqs: string[];     // compliance requirements satisfied
  changeClass: string;
  compensation?: string; // compensation logic description
  guardRules: string[]; // rule IDs that guard this step
};

// ─── Graph node ───────────────────────────────────────────────────────────────

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
  runbookStale?: boolean;
  tests: TestSuite;
  dl: string | null;
  pt: boolean;        // paper_trail
  arch: boolean;      // archival
  pm: boolean;        // pending migration
  sm: StateMachine;
  routes: Route[];
  telem: string[];
  money: MoneyField[];
  auth: boolean;
  oban: string[];
  rl: boolean;        // rate limited
  flags: FeatureFlag[];
  mod: string;        // last modified date
  steps?: TransferStep[]; // for transfers/reactors
};

// ─── Edge relation types (per spec section 8) ─────────────────────────────────

export type EdgeRelation =
  | 'sequence'      // ──────────▶  step to step inside Transfer
  | 'async'         // - - - - - ▶  crosses process boundary
  | 'guard'         // ···········▶  Rule to step (dotted)
  | 'eligibleIf'    // · ─ · ─ · ▶  Blueprint to Rule dependency
  | 'compensation'  // ══════════▶  saga rollback
  | 'error'         // ━ ━ ━ ━ ━ ▶  failure path
  | 'reads'         // ──────────◇  non-mutating resource access
  | 'writes'        // ══════════◆  mutating
  | 'triggers'      // ──────────○  input node to Transfer/Reactor
  | 'calls'         // legacy — general relationship
  | 'enforces'      // legacy — policy enforcement
  | 'references';   // legacy — soft reference

export type GraphEdge = {
  f: string;
  t: string;
  r: EdgeRelation;
};

// ─── Lens (removed — spec says no lenses required) ────────────────────────────

export type Lens = 'default' | 'trace';

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
  zoomLevel: 1 | 2 | 3;  // domain map | flow map | step detail
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
