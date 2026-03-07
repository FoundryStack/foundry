import type { GraphNode, GraphEdge, Scenario, FeedCard } from './types';

// ─── Node registry ────────────────────────────────────────────────────────────

export const NODES: Record<string, GraphNode> = {
  player: {
    id: 'player', name: 'Player', type: 'resource', domain: 'Identity',
    module: 'MyApp.Identity.Player', sensitive: true, gap: false, cov: 100,
    desc: 'Core identity resource. PII-bearing; encrypted at rest. Authentication subject for ash_authentication.',
    attrs: [
      { n: 'id', t: 'UUID', d: 'Primary key', pii: false, mon: false, sen: false },
      { n: 'email', t: ':ci_string', d: 'Login email — case-insensitive', pii: true, mon: false, sen: true },
      { n: 'display_name', t: ':string', d: 'Public username', pii: false, mon: false, sen: false },
      { n: 'kyc_status', t: ':atom', d: 'unverified|pending|verified', pii: false, mon: false, sen: false },
      { n: 'self_excluded', t: ':boolean', d: 'Permanent self-exclusion flag', pii: false, mon: false, sen: true },
    ],
    actions: [
      { n: 'register', c: 'sensitive' }, { n: 'verify_kyc', c: 'compliance' },
      { n: 'self_exclude', c: 'sensitive' }, { n: 'read', c: 'structural' },
    ],
    reqs: ['RG-UK-019', 'GDPR-001'], adrs: ['ADR-005', 'ADR-002'],
    runbook: 'docs/runbooks/player.md',
    tests: { p: true, s: true, e: true },
    dl: 'ash_postgres', pt: true, arch: true, pm: false,
    sm: { on: true, states: ['unverified', 'pending', 'verified', 'excluded'], tr: [
      { f: 'unverified', t: 'pending', ev: 'submit_kyc' },
      { f: 'pending', t: 'verified', ev: 'kyc_approved' },
      { f: 'any', t: 'excluded', ev: 'self_exclude' },
    ], attr: 'kyc_status' },
    routes: [{ r: '/players/:id', m: 'GET', auth: true }],
    telem: ['my_app', 'identity', 'player'], money: [],
    auth: true, oban: [], rl: true, flags: [], mod: '2026-03-03',
  },
  wallet: {
    id: 'wallet', name: 'Wallet', type: 'resource', domain: 'Finance',
    module: 'MyApp.Finance.Wallet', sensitive: true, gap: false, cov: 100,
    desc: 'Holds player balance. Debited/credited exclusively via Transfer operations. Soft-delete only. Never goes negative.',
    attrs: [
      { n: 'id', t: 'UUID', d: 'Primary key', pii: false, mon: false, sen: false },
      { n: 'balance', t: 'Ash.Type.Money', d: 'Current balance', pii: false, mon: true, sen: true },
      { n: 'player_id', t: 'UUID', d: 'Owner reference', pii: false, mon: false, sen: false },
      { n: 'currency', t: ':atom', d: 'ISO-4217 code', pii: false, mon: false, sen: false },
      { n: 'locked_at', t: 'DateTime', d: 'Set when withdrawal in progress', pii: false, mon: false, sen: false },
    ],
    actions: [
      { n: 'credit', c: 'sensitive' }, { n: 'debit', c: 'sensitive' },
      { n: 'lock', c: 'behavioral' }, { n: 'read', c: 'structural' },
    ],
    reqs: ['RG-UK-014', 'RG-MGA-007'], adrs: ['ADR-005', 'ADR-002'],
    runbook: 'docs/runbooks/wallet.md',
    tests: { p: true, s: true, e: true },
    dl: 'ash_postgres', pt: true, arch: true, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: ['my_app', 'finance', 'wallet'],
    money: [{ n: 'balance', t: 'Ash.Type.Money', cldr: 'MyApp.Cldr' }],
    auth: false, oban: [], rl: false, flags: [], mod: '2026-03-01',
  },
  ledger: {
    id: 'ledger', name: 'LedgerEntry', type: 'resource', domain: 'Finance',
    module: 'MyApp.Finance.LedgerEntry', sensitive: true, gap: false, cov: 100,
    desc: 'Immutable double-entry ledger record. Created only on Transfer completion. Never hard-deleted.',
    attrs: [
      { n: 'id', t: 'UUID', d: 'Primary key', pii: false, mon: false, sen: false },
      { n: 'amount', t: 'Ash.Type.Money', d: 'Transaction amount', pii: false, mon: true, sen: true },
      { n: 'direction', t: ':atom', d: 'debit or credit', pii: false, mon: false, sen: false },
      { n: 'transfer_id', t: 'UUID', d: 'Originating transfer', pii: false, mon: false, sen: false },
      { n: 'wallet_id', t: 'UUID', d: 'Affected wallet', pii: false, mon: false, sen: false },
    ],
    actions: [{ n: 'create', c: 'sensitive' }, { n: 'read', c: 'structural' }],
    reqs: ['RG-UK-014', 'AML-003'], adrs: ['ADR-005'],
    runbook: null, tests: { p: true, s: true, e: true },
    dl: 'ash_postgres', pt: true, arch: true, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: ['my_app', 'finance', 'ledger_entry'],
    money: [{ n: 'amount', t: 'Ash.Type.Money', cldr: 'MyApp.Cldr' }],
    auth: false, oban: [], rl: false, flags: [], mod: '2026-02-28',
  },
  withdraw: {
    id: 'withdraw', name: 'WithdrawalTransfer', type: 'transfer', domain: 'Finance',
    module: 'MyApp.Finance.WithdrawalTransfer', sensitive: true, gap: false, cov: 88,
    desc: 'Multi-step Reactor executing player withdrawal. Enforces KYC, cooling-off, balance checks. Idempotent.',
    attrs: [],
    actions: [{ n: 'execute', c: 'sensitive' }, { n: 'rollback', c: 'sensitive' }],
    reqs: ['RG-UK-014', 'RG-MGA-007'], adrs: ['ADR-002', 'ADR-005'],
    runbook: 'docs/runbooks/withdrawal_transfer.md',
    tests: { p: true, s: true, e: false },
    dl: 'ash_postgres', pt: true, arch: true, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: ['my_app', 'finance', 'withdrawal_transfer'],
    money: [{ n: 'amount', t: 'Ash.Type.Money', cldr: 'MyApp.Cldr' }],
    auth: false, oban: [], rl: true, flags: [], mod: '2026-03-02',
  },
  deposit: {
    id: 'deposit', name: 'DepositTransfer', type: 'transfer', domain: 'Finance',
    module: 'MyApp.Finance.DepositTransfer', sensitive: false, gap: false, cov: 85,
    desc: 'Processes incoming deposits from payment gateway. Triggers AML screening asynchronously via Oban.',
    attrs: [],
    actions: [{ n: 'execute', c: 'behavioral' }],
    reqs: ['AML-003'], adrs: ['ADR-002'],
    runbook: null, tests: { p: true, s: true, e: false },
    dl: 'ash_postgres', pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [{ r: '/deposits', m: 'POST', auth: true }],
    telem: ['my_app', 'finance', 'deposit_transfer'],
    money: [], auth: false, oban: [], rl: false, flags: [], mod: '2026-02-25',
  },
  kyccheck: {
    id: 'kyccheck', name: 'KycCheck', type: 'rule', domain: 'Compliance',
    module: 'MyApp.Compliance.KycCheck', sensitive: false, gap: true, cov: 40,
    desc: 'Validates KYC status before high-value actions. Blocks withdrawals for unverified players.',
    attrs: [],
    actions: [{ n: 'check', c: 'behavioral' }],
    reqs: ['RG-UK-019', 'RG-MGA-011'], adrs: ['ADR-005'],
    runbook: null, tests: { p: false, s: false, e: false },
    dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: ['my_app', 'compliance', 'kyc_check'],
    money: [], auth: false, oban: [], rl: false,
    flags: [{ n: 'strict_kyc_mode', adr: 'ADR-013' }], mod: '2026-02-20',
  },
  rgcheck: {
    id: 'rgcheck', name: 'ResponsibleGamingCheck', type: 'rule', domain: 'Compliance',
    module: 'MyApp.Compliance.ResponsibleGamingCheck', sensitive: false, gap: true, cov: 55,
    desc: 'Enforces RG limits. Checks daily/weekly/monthly spend and self-exclusion before allowing play.',
    attrs: [],
    actions: [{ n: 'evaluate', c: 'behavioral' }],
    reqs: ['RG-UK-031', 'RG-MGA-022'], adrs: ['ADR-005'],
    runbook: null, tests: { p: true, s: false, e: false },
    dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: ['my_app', 'compliance', 'responsible_gaming_check'],
    money: [], auth: false, oban: [], rl: false, flags: [], mod: '2026-02-18',
  },
  amlscreen: {
    id: 'amlscreen', name: 'AmlScreeningReactor', type: 'reactor', domain: 'Compliance',
    module: 'MyApp.Compliance.AmlScreeningReactor', sensitive: false, gap: false, cov: 90,
    desc: 'Async AML screening via Oban. Triggered post-deposit. Submits SAR records for flagged transactions.',
    attrs: [],
    actions: [{ n: 'perform', c: 'behavioral' }],
    reqs: ['AML-003', 'AML-007'], adrs: ['ADR-002'],
    runbook: 'docs/runbooks/aml_screening.md',
    tests: { p: true, s: true, e: false },
    dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: ['my_app', 'compliance', 'aml_screening'],
    money: [], auth: false, oban: ['aml_screening'], rl: false, flags: [], mod: '2026-03-01',
  },
  limit: {
    id: 'limit', name: 'SpendingLimit', type: 'resource', domain: 'Identity',
    module: 'MyApp.Identity.SpendingLimit', sensitive: false, gap: true, cov: 30,
    desc: 'Per-player spending limits for daily, weekly and monthly periods. Compliance-critical.',
    attrs: [
      { n: 'player_id', t: 'UUID', d: 'Owner reference', pii: false, mon: false, sen: false },
      { n: 'period', t: ':atom', d: 'daily|weekly|monthly', pii: false, mon: false, sen: false },
      { n: 'amount', t: 'Ash.Type.Money', d: 'Limit ceiling', pii: false, mon: true, sen: false },
    ],
    actions: [
      { n: 'set', c: 'compliance' }, { n: 'reduce', c: 'compliance' }, { n: 'read', c: 'structural' },
    ],
    reqs: ['RG-UK-031', 'RG-MGA-022'], adrs: ['ADR-005'],
    runbook: null, tests: { p: false, s: false, e: false },
    dl: 'ash_postgres', pt: false, arch: false, pm: true,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: ['my_app', 'identity', 'spending_limit'],
    money: [{ n: 'amount', t: 'Ash.Type.Money', cldr: 'MyApp.Cldr' }],
    auth: false, oban: [], rl: false, flags: [], mod: '2026-02-15',
  },
  round: {
    id: 'round', name: 'GameRound', type: 'resource', domain: 'Game',
    module: 'MyApp.Game.GameRound', sensitive: false, gap: false, cov: 75,
    desc: 'Single game round lifecycle from initiation to settlement. Includes FSM.',
    attrs: [
      { n: 'id', t: 'UUID', d: 'Primary key', pii: false, mon: false, sen: false },
      { n: 'status', t: ':atom', d: 'State machine attribute', pii: false, mon: false, sen: false },
      { n: 'wager', t: 'Ash.Type.Money', d: 'Initial wager', pii: false, mon: true, sen: false },
      { n: 'result_amount', t: 'Ash.Type.Money', d: 'Settlement amount', pii: false, mon: true, sen: false },
    ],
    actions: [
      { n: 'initiate', c: 'behavioral' }, { n: 'settle', c: 'behavioral' }, { n: 'void', c: 'behavioral' },
    ],
    reqs: [], adrs: ['ADR-002'],
    runbook: null, tests: { p: true, s: true, e: false },
    dl: 'ash_postgres', pt: false, arch: false, pm: false,
    sm: { on: true, states: ['open', 'settled', 'void'], tr: [
      { f: 'open', t: 'settled', ev: 'settle' },
      { f: 'open', t: 'void', ev: 'void' },
    ], attr: 'status' },
    routes: [], telem: ['my_app', 'game', 'game_round'],
    money: [
      { n: 'wager', t: 'Ash.Type.Money', cldr: 'MyApp.Cldr' },
      { n: 'result_amount', t: 'Ash.Type.Money', cldr: 'MyApp.Cldr' },
    ],
    auth: false, oban: [], rl: false,
    flags: [{ n: 'high_stake_mode', adr: 'ADR-013' }], mod: '2026-02-28',
  },
};

// ─── Domain ordering ──────────────────────────────────────────────────────────

export const DOMAIN_ORDER = ['Finance', 'Identity', 'Compliance', 'Game'] as const;

// ─── Edges ────────────────────────────────────────────────────────────────────

export const EDGES: GraphEdge[] = [
  { f: 'player', t: 'wallet', r: 'calls' },
  { f: 'player', t: 'kyccheck', r: 'enforces' },
  { f: 'player', t: 'rgcheck', r: 'enforces' },
  { f: 'player', t: 'limit', r: 'references' },
  { f: 'wallet', t: 'withdraw', r: 'calls' },
  { f: 'wallet', t: 'deposit', r: 'calls' },
  { f: 'ledger', t: 'withdraw', r: 'calls' },
  { f: 'ledger', t: 'deposit', r: 'calls' },
  { f: 'deposit', t: 'amlscreen', r: 'triggers' },
  { f: 'round', t: 'withdraw', r: 'calls' },
  { f: 'kyccheck', t: 'withdraw', r: 'enforces' },
  { f: 'rgcheck', t: 'limit', r: 'enforces' },
];

// ─── Requirement metadata ─────────────────────────────────────────────────────

export const REQ_META: Record<string, { label: string }> = {
  'RG-UK-014': { label: 'UK — Withdrawal controls' },
  'RG-UK-019': { label: 'UK — KYC verification' },
  'RG-UK-031': { label: 'UK — Spending limits' },
  'RG-MGA-007': { label: 'MGA — Wallet integrity' },
  'RG-MGA-011': { label: 'MGA — KYC high-value' },
  'RG-MGA-022': { label: 'MGA — Player protection' },
  'AML-003': { label: 'AML — Transaction monitoring' },
  'AML-007': { label: 'AML — SAR reporting' },
  'GDPR-001': { label: 'GDPR — PII minimisation' },
};

// ─── Scenarios ────────────────────────────────────────────────────────────────

export const SCENARIOS: Record<string, Scenario> = {
  withdraw: {
    label: 'Player withdraws £500',
    steps: [
      { id: 'player', action: 'read', note: 'Resolve identity + check self_excluded', reqs: ['RG-UK-019'], gap: false },
      { id: 'kyccheck', action: 'check', note: 'Assert KYC verified — blocks unverified', reqs: ['RG-UK-019', 'RG-MGA-011'], gap: true, gapNote: 'Missing scenario + e2e tests' },
      { id: 'rgcheck', action: 'evaluate', note: 'Check daily/weekly/monthly limits', reqs: ['RG-UK-031', 'RG-MGA-022'], gap: true, gapNote: 'Missing scenario tests' },
      { id: 'limit', action: 'read', note: 'Read SpendingLimit ceilings', reqs: ['RG-UK-031'], gap: true, gapNote: '30% coverage + pending migration' },
      { id: 'wallet', action: 'debit', note: 'Debit wallet — sensitive, dual approval', reqs: ['RG-UK-014', 'RG-MGA-007'], gap: false },
      { id: 'withdraw', action: 'execute', note: 'WithdrawalTransfer reactor fires — idempotent', reqs: ['RG-UK-014', 'RG-MGA-007'], gap: false },
      { id: 'ledger', action: 'create', note: 'Immutable ledger entry written', reqs: ['RG-UK-014', 'AML-003'], gap: false },
    ],
  },
  deposit: {
    label: 'Player deposits via card',
    steps: [
      { id: 'player', action: 'read', note: 'Resolve player identity', reqs: ['RG-UK-019'], gap: false },
      { id: 'deposit', action: 'execute', note: 'DepositTransfer executes — credits wallet', reqs: ['AML-003'], gap: false },
      { id: 'wallet', action: 'credit', note: 'Wallet credited — sensitive', reqs: ['RG-MGA-007'], gap: false },
      { id: 'ledger', action: 'create', note: 'Ledger entry written', reqs: ['AML-003'], gap: false },
      { id: 'amlscreen', action: 'perform', note: 'Async AML screening enqueued via Oban', reqs: ['AML-003', 'AML-007'], gap: false },
    ],
  },
  register: {
    label: 'New player registration',
    steps: [
      { id: 'player', action: 'register', note: 'Create player — sensitive, paper_trail', reqs: ['GDPR-001', 'RG-UK-019'], gap: false },
      { id: 'kyccheck', action: 'check', note: 'Initial KYC set to unverified', reqs: ['RG-UK-019'], gap: true, gapNote: 'No scenario tests for initial state' },
      { id: 'limit', action: 'set', note: 'Default spending limits applied', reqs: ['RG-UK-031'], gap: true, gapNote: '30% coverage + pending migration' },
      { id: 'wallet', action: 'read', note: 'Wallet created with zero balance', reqs: ['RG-MGA-007'], gap: false },
    ],
  },
  play: {
    label: 'Player initiates game round',
    steps: [
      { id: 'player', action: 'read', note: 'Verify player not self-excluded', reqs: ['RG-UK-019'], gap: false },
      { id: 'rgcheck', action: 'evaluate', note: 'Check spend limits before round', reqs: ['RG-UK-031', 'RG-MGA-022'], gap: true, gapNote: 'Missing scenario tests' },
      { id: 'round', action: 'initiate', note: 'GameRound created in open state', reqs: [], gap: false },
      { id: 'wallet', action: 'debit', note: 'Wager amount deducted', reqs: ['RG-MGA-007'], gap: false },
    ],
  },
};

// ─── Canvas layout positions ──────────────────────────────────────────────────

export const NODE_LAYOUT: Record<string, { x: number; y: number }> = {
  player:    { x: 60,  y: 240 },
  wallet:    { x: 260, y: 120 },
  ledger:    { x: 260, y: 300 },
  withdraw:  { x: 460, y: 80  },
  deposit:   { x: 460, y: 240 },
  kyccheck:  { x: 460, y: 390 },
  rgcheck:   { x: 640, y: 300 },
  amlscreen: { x: 640, y: 190 },
  limit:     { x: 640, y: 420 },
  round:     { x: 260, y: 440 },
};

// ─── Visual constants ─────────────────────────────────────────────────────────

export const NODE_W = 148;
export const NODE_H = 58;

export const TYPE_COLOR: Record<string, string> = {
  resource: '#60a5fa',
  transfer: '#2dd4bf',
  rule: '#f59e0b',
  reactor: '#a78bfa',
};

export const TYPE_ABBR: Record<string, string> = {
  resource: 'R',
  transfer: 'T',
  rule: 'Rl',
  reactor: 'Re',
};

export const DOMAIN_FILL: Record<string, string> = {
  Finance: 'rgba(96,165,250,.025)',
  Identity: 'rgba(45,212,191,.025)',
  Compliance: 'rgba(245,158,11,.025)',
  Game: 'rgba(167,139,250,.025)',
};

export const DOMAIN_STROKE: Record<string, string> = {
  Finance: 'rgba(96,165,250,.18)',
  Identity: 'rgba(45,212,191,.18)',
  Compliance: 'rgba(245,158,11,.18)',
  Game: 'rgba(167,139,250,.18)',
};

// ─── Initial activity feed ────────────────────────────────────────────────────

export const INITIAL_FEED: FeedCard[] = [
  {
    id: 'f1', type: 'ci', time: '2m ago',
    body: '<strong>main@a3f9d12</strong> — all lint, compliance and property tests green.',
  },
  {
    id: 'f2', type: 'proposal', time: '14m ago',
    body: '<strong>Op.AddAttribute</strong> proposed: add <code>SpendingLimit.confirmed_at</code>. Classified :compliance. <span style="color:var(--yw)">Awaiting ADR link.</span>',
  },
  {
    id: 'f3', type: 'question', time: '22m ago',
    body: 'What compliance requirements apply to WithdrawalTransfer?',
  },
  {
    id: 'f4', type: 'response', time: '22m ago', conf: 'HIGH',
    body: '<strong>WithdrawalTransfer</strong> is governed by <code>RG-UK-014</code> and <code>RG-MGA-007</code>. E2E coverage is <strong style="color:var(--yw)">missing</strong>.',
  },
  {
    id: 'f5', type: 'error', time: '1h ago',
    body: '<code>:context_build_failed</code> — project had compilation errors. Resolved after <code>mix compile</code>.',
  },
];
