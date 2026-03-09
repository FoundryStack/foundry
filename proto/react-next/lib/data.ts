import type { GraphNode, GraphEdge, Scenario, FeedCard } from './types';

// ─── Node resolution for HoverCard (includes step/state/output nodes) ─────────

export type ResolvedNode = GraphNode | {
  id: string;
  name: string;
  type: 'step' | 'state' | 'output';
  domain: string;
  cov: number;
  gap: boolean;
  sensitive: boolean;
  desc: string;
  attrs: never[];
  actions: never[];
  reqs: string[];
  adrs: never[];
  runbook: null;
  tests: { p: boolean; s: boolean; e: boolean };
  dl: null;
  pt: false;
  arch: false;
  pm: false;
  sm: { on: false; states: never[]; tr: never[]; attr: null };
  routes: never[];
  telem: never[];
  money: never[];
  auth: false;
  oban: never[];
  rl: false;
  flags: never[];
  mod: string;
};

export function getNodeForHover(nodeId: string): ResolvedNode | null {
  const n = NODES[nodeId];
  if (n) return n;

  // Step node - find parent transfer
  for (const node of Object.values(NODES)) {
    if ((node.type === 'transfer' || node.type === 'reactor') && node.steps) {
      const step = node.steps.find((s) => s.id === nodeId);
      if (step) {
        return {
          id: step.id,
          name: step.name,
          type: 'step',
          domain: node.domain,
          cov: node.cov,
          gap: node.gap,
          sensitive: node.sensitive,
          desc: `Step in ${node.name}`,
          attrs: [],
          actions: [],
          reqs: step.reqs,
          adrs: [],
          runbook: null,
          tests: node.tests,
          dl: null,
          pt: false,
          arch: false,
          pm: false,
          sm: { on: false, states: [], tr: [], attr: null },
          routes: [],
          telem: [],
          money: [],
          auth: false,
          oban: [],
          rl: false,
          flags: [],
          mod: node.mod,
        };
      }
    }
  }

  // State node - find parent resource
  for (const node of Object.values(NODES)) {
    if (node.sm?.on && node.sm.states) {
      const state = node.sm.states.find((s) => s.id === nodeId);
      if (state) {
        return {
          id: state.id,
          name: state.name,
          type: 'state',
          domain: node.domain,
          cov: node.cov,
          gap: node.gap,
          sensitive: node.sensitive,
          desc: `FSM state in ${node.name}`,
          attrs: [],
          actions: [],
          reqs: [],
          adrs: [],
          runbook: null,
          tests: node.tests,
          dl: null,
          pt: false,
          arch: false,
          pm: false,
          sm: { on: false, states: [], tr: [], attr: null },
          routes: [],
          telem: [],
          money: [],
          auth: false,
          oban: [],
          rl: false,
          flags: [],
          mod: node.mod,
        };
      }
    }
  }

  // Output node
  if (nodeId.startsWith('withdraw-')) {
    const withdraw = NODES['withdraw'];
    if (withdraw) {
      const label = nodeId.includes('commit') ? 'Committed' : nodeId.includes('error') ? 'Error' : 'Compensated';
      return {
        id: nodeId,
        name: label,
        type: 'output',
        domain: withdraw.domain,
        cov: withdraw.cov,
        gap: withdraw.gap,
        sensitive: withdraw.sensitive,
        desc: `Terminal outcome of ${withdraw.name}`,
        attrs: [],
        actions: [],
        reqs: [],
        adrs: [],
        runbook: null,
        tests: withdraw.tests,
        dl: null,
        pt: false,
        arch: false,
        pm: false,
        sm: { on: false, states: [], tr: [], attr: null },
        routes: [],
        telem: [],
        money: [],
        auth: false,
        oban: [],
        rl: false,
        flags: [],
        mod: withdraw.mod,
      };
    }
  }

  // Cluster node (cluster-identity, cluster-finance, cluster-withdraw, etc.)
  if (nodeId.startsWith('cluster-')) {
    const suffix = nodeId.replace('cluster-', '');
    const domainMap: Record<string, string> = {
      identity: 'Identity',
      finance: 'Finance',
      compliance: 'Compliance',
      game: 'Game',
      player: 'Identity',
      withdraw: 'Finance',
      deposit: 'Finance',
      amlscreen: 'Compliance',
    };
    const domain = domainMap[suffix] ?? domainMap[suffix.split('-')[0]] ?? 'Identity';
    const transferNames: Record<string, string> = {
      withdraw: 'WithdrawalTransfer',
      deposit: 'DepositTransfer',
      amlscreen: 'AmlScreeningReactor',
    };
    const clusterName = transferNames[suffix] ?? NODES['player']?.name ?? domain;
    return {
      id: nodeId,
      name: ['identity', 'finance', 'compliance', 'game'].includes(suffix) ? domain : clusterName,
      type: 'resource' as const,
      domain,
      module: '',
      cov: 0,
      gap: false,
      sensitive: false,
      desc: `Domain cluster: ${domain}`,
      attrs: [],
      actions: [],
      reqs: [],
      adrs: [],
      runbook: null,
      tests: { p: false, s: false, e: false },
      dl: null,
      pt: false,
      arch: false,
      pm: false,
      sm: { on: false, states: [], tr: [], attr: null },
      routes: [],
      telem: [],
      money: [],
      auth: false,
      oban: [],
      rl: false,
      flags: [],
      mod: '',
    } as ResolvedNode;
  }

  return null;
}

/** Maps entity id to graph node id (for compounds, entity is inside cluster). */
export function getGraphNodeId(entityId: string): string {
  if (['withdraw', 'deposit', 'amlscreen', 'player'].includes(entityId)) return `cluster-${entityId}`;
  return entityId;
}

/** Maps any node id (cluster, step, state, output) to the primary entity id for drawer/details. */
export function getPrimaryNodeId(nodeId: string): string | null {
  if (NODES[nodeId]) return nodeId;
  if (nodeId.startsWith('cluster-')) {
    const suffix = nodeId.replace('cluster-', '');
    if (['withdraw', 'deposit', 'amlscreen', 'player'].includes(suffix)) return suffix;
    return null; // domain clusters have no single entity
  }
  // Step -> parent transfer
  for (const node of Object.values(NODES)) {
    if ((node.type === 'transfer' || node.type === 'reactor') && node.steps?.some((s) => s.id === nodeId))
      return node.id;
  }
  // State -> parent resource
  for (const node of Object.values(NODES)) {
    if (node.sm?.states?.some((s) => s.id === nodeId)) return node.id;
  }
  // Output -> parent transfer
  if (nodeId.startsWith('withdraw-')) return 'withdraw';
  return null;
}

// ─── Domain colors (per spec section 7) ───────────────────────────────────────

export const DOMAIN_COLOR: Record<string, string> = {
  Finance:    '#60a5fa',  // blue
  Identity:   '#34d399',  // green
  Compliance: '#fbbf24',  // amber
  Game:       '#c084fc',  // purple
};

export const DOMAIN_FILL: Record<string, string> = {
  Finance:    'rgba(96,165,250,.025)',
  Identity:   'rgba(52,211,153,.025)',
  Compliance: 'rgba(251,191,36,.025)',
  Game:       'rgba(192,132,252,.025)',
};

export const DOMAIN_STROKE: Record<string, string> = {
  Finance:    'rgba(96,165,250,.18)',
  Identity:   'rgba(52,211,153,.18)',
  Compliance: 'rgba(251,191,36,.18)',
  Game:       'rgba(192,132,252,.18)',
};

// ─── Type icons (per spec section 3) ──────────────────────────────────────────

export const TYPE_ICON: Record<string, string> = {
  resource:     '⬡',
  transfer:     '⇄',
  rule:         '◈',
  reactor:      '⚡',
  input:        '▶',
  output:       '⟐',
  blueprint:    '◇',
  liveresource: '▣',
  provider:     '⬚',
  step:         '⇄',
  state:        '○',
};

// ─── Type abbreviations (single-char / icon for badges) ─────────────────────────

export const TYPE_ABBR = TYPE_ICON;

// ─── Type colors (per spec, for badges and highlights) ─────────────────────────

export const TYPE_COLOR: Record<string, string> = {
  resource:     '#60a5fa',  // blue
  transfer:     '#34d399',  // green
  rule:         '#fbbf24',  // amber
  reactor:      '#c084fc',  // purple
  input:        '#38bdf8',  // light blue
  output:       '#94a3b8',  // slate
  blueprint:    '#a78bfa',  // violet
  liveresource: '#c084fc',  // purple
  provider:     '#f59e0b',  // amber
  step:         '#34d399',  // green (transfer step)
  state:        '#60a5fa',  // blue (FSM state)
};

// ─── Node registry ────────────────────────────────────────────────────────────

export const NODES: Record<string, GraphNode> = {
  // ══════════════════════════════════════════════════════════════════════════
  // IDENTITY DOMAIN
  // ══════════════════════════════════════════════════════════════════════════

  'input-register': {
    id: 'input-register', name: '/api/register', type: 'input', domain: 'Identity',
    module: '', sensitive: false, gap: false, cov: 100,
    desc: 'Player registration endpoint',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: true, s: true, e: true }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [{ r: '/api/register', m: 'POST', auth: false }],
    telem: [], money: [], auth: false, oban: [], rl: true, flags: [], mod: '2026-03-03',
  },

  'input-sessions': {
    id: 'input-sessions', name: '/api/sessions', type: 'input', domain: 'Identity',
    module: '', sensitive: false, gap: false, cov: 100,
    desc: 'Session management endpoint',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: true, s: true, e: true }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [{ r: '/api/sessions', m: 'POST', auth: false }],
    telem: [], money: [], auth: false, oban: [], rl: true, flags: [], mod: '2026-03-03',
  },

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
    sm: {
      on: true,
      states: [
        { id: 'player-unverified', name: 'unverified', marker: 'normal' },
        { id: 'player-pending', name: 'pending', marker: 'normal' },
        { id: 'player-verified', name: 'verified', marker: 'active' },
        { id: 'player-excluded', name: 'excluded', marker: 'trap' },
      ],
      tr: [
        { f: 'unverified', t: 'pending', ev: 'submit_kyc' },
        { f: 'pending', t: 'verified', ev: 'kyc_approved' },
        { f: 'any', t: 'excluded', ev: 'self_exclude' },
      ],
      attr: 'kyc_status',
    },
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
      { n: 'balance', t: 'Money', d: 'Current balance', pii: false, mon: true, sen: true },
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
    money: [{ n: 'balance', t: 'Money', cldr: 'MyApp.Cldr' }],
    auth: false, oban: [], rl: false, flags: [], mod: '2026-03-01',
  },

  limit: {
    id: 'limit', name: 'SpendingLimit', type: 'resource', domain: 'Identity',
    module: 'MyApp.Identity.SpendingLimit', sensitive: false, gap: true, cov: 30,
    desc: 'Per-player spending limits for daily, weekly and monthly periods. Compliance-critical.',
    attrs: [
      { n: 'player_id', t: 'UUID', d: 'Owner reference', pii: false, mon: false, sen: false },
      { n: 'period', t: ':atom', d: 'daily|weekly|monthly', pii: false, mon: false, sen: false },
      { n: 'amount', t: 'Money', d: 'Limit ceiling', pii: false, mon: true, sen: false },
    ],
    actions: [
      { n: 'set', c: 'compliance' }, { n: 'reduce', c: 'compliance' }, { n: 'read', c: 'structural' },
    ],
    reqs: ['RG-UK-031', 'RG-MGA-022'], adrs: ['ADR-005'],
    runbook: null, tests: { p: false, s: false, e: false },
    dl: 'ash_postgres', pt: false, arch: false, pm: true,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: ['my_app', 'identity', 'spending_limit'],
    money: [{ n: 'amount', t: 'Money', cldr: 'MyApp.Cldr' }],
    auth: false, oban: [], rl: false, flags: [], mod: '2026-02-15',
  },

  'player-live': {
    id: 'player-live', name: 'PlayerLiveResource', type: 'liveresource', domain: 'Identity',
    module: 'MyApp.Identity.PlayerLiveResource', sensitive: false, gap: false, cov: 85,
    desc: 'Back-office admin UI for Player management',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: false, s: true, e: false }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: [], money: [], auth: true, oban: [], rl: false, flags: [], mod: '2026-03-01',
  },

  // ══════════════════════════════════════════════════════════════════════════
  // FINANCE DOMAIN
  // ══════════════════════════════════════════════════════════════════════════

  'input-withdraw': {
    id: 'input-withdraw', name: 'POST /withdraw', type: 'input', domain: 'Finance',
    module: '', sensitive: false, gap: false, cov: 100,
    desc: 'Withdrawal request endpoint',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: true, s: true, e: true }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [{ r: '/withdraw', m: 'POST', auth: true, rl: true, idem: true }],
    telem: [], money: [], auth: true, oban: [], rl: true, flags: [], mod: '2026-03-02',
  },

  'input-webhook-pg': {
    id: 'input-webhook-pg', name: 'Webhook: payment_gateway', type: 'input', domain: 'Finance',
    module: '', sensitive: false, gap: false, cov: 100,
    desc: 'Payment gateway webhook receiver',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: true, s: true, e: true }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [{ r: '/webhooks/payment_gateway', m: 'POST', auth: false }],
    telem: [], money: [], auth: false, oban: [], rl: false, flags: [], mod: '2026-03-02',
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
    money: [{ n: 'amount', t: 'Money', cldr: 'MyApp.Cldr' }],
    auth: false, oban: [], rl: true, flags: [], mod: '2026-03-02',
    steps: [
      { id: 'w-validate', name: 'validate', reads: ['player'], writes: [], reqs: ['RG-UK-019'], changeClass: 'behavioral', guardRules: ['kyccheck'] },
      { id: 'w-check-limits', name: 'check_limits', reads: ['limit'], writes: [], reqs: ['RG-UK-031', 'RG-MGA-022'], changeClass: 'behavioral', guardRules: ['rgcheck'] },
      { id: 'w-debit', name: 'debit', reads: [], writes: ['wallet', 'ledger'], reqs: ['RG-UK-014', 'RG-MGA-007'], changeClass: 'sensitive', compensation: 'credit wallet back', guardRules: [] },
      { id: 'w-notify', name: 'notify', reads: [], writes: [], reqs: [], changeClass: 'behavioral', guardRules: [] },
    ],
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
    steps: [
      { id: 'd-validate', name: 'validate', reads: ['player'], writes: [], reqs: [], changeClass: 'behavioral', guardRules: [] },
      { id: 'd-credit', name: 'credit', reads: [], writes: ['wallet', 'ledger'], reqs: ['AML-003'], changeClass: 'sensitive', guardRules: [] },
      { id: 'd-enqueue-aml', name: 'enqueue_aml', reads: [], writes: [], reqs: ['AML-003'], changeClass: 'behavioral', guardRules: [] },
    ],
  },

  ledger: {
    id: 'ledger', name: 'LedgerEntry', type: 'resource', domain: 'Finance',
    module: 'MyApp.Finance.LedgerEntry', sensitive: true, gap: false, cov: 100,
    desc: 'Immutable double-entry ledger record. Created only on Transfer completion. Never hard-deleted.',
    attrs: [
      { n: 'id', t: 'UUID', d: 'Primary key', pii: false, mon: false, sen: false },
      { n: 'amount', t: 'Money', d: 'Transaction amount', pii: false, mon: true, sen: true },
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
    money: [{ n: 'amount', t: 'Money', cldr: 'MyApp.Cldr' }],
    auth: false, oban: [], rl: false, flags: [], mod: '2026-02-28',
  },

  'pg-adapter': {
    id: 'pg-adapter', name: 'PaymentGatewayAdapter', type: 'provider', domain: 'Finance',
    module: 'MyApp.Finance.PaymentGatewayAdapter', sensitive: false, gap: false, cov: 95,
    desc: 'External payment gateway integration via Req-based adapter',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: true, s: true, e: true }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: [], money: [], auth: false, oban: [], rl: false, flags: [], mod: '2026-03-01',
  },

  // ══════════════════════════════════════════════════════════════════════════
  // COMPLIANCE DOMAIN
  // ══════════════════════════════════════════════════════════════════════════

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
    flags: [{ n: 'strict_kyc_mode', adr: 'ADR-013', type: 'compliance' }], mod: '2026-02-20',
  },

  rgcheck: {
    id: 'rgcheck', name: 'RGCheck', type: 'rule', domain: 'Compliance',
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

  'input-cron-aml': {
    id: 'input-cron-aml', name: 'Scheduler: cron 0 * * * *', type: 'input', domain: 'Compliance',
    module: '', sensitive: false, gap: false, cov: 100,
    desc: 'Hourly AML screening cron job',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: true, s: true, e: true }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: [], money: [], auth: false, oban: [], rl: false, flags: [], mod: '2026-03-01',
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
    steps: [
      { id: 'aml-fetch', name: 'fetch', reads: ['ledger'], writes: [], reqs: ['AML-003'], changeClass: 'behavioral', guardRules: [] },
      { id: 'aml-submit', name: 'submit', reads: [], writes: [], reqs: ['AML-007'], changeClass: 'behavioral', guardRules: [] },
      { id: 'aml-record', name: 'record_sar', reads: [], writes: [], reqs: ['AML-007'], changeClass: 'sensitive', guardRules: [] },
    ],
  },

  // ══════════════════════════════════════════════════════════════════════════
  // GAME DOMAIN
  // ══════════════════════════════════════════════════════════════════════════

  'input-rounds': {
    id: 'input-rounds', name: 'POST /api/rounds', type: 'input', domain: 'Game',
    module: '', sensitive: false, gap: false, cov: 100,
    desc: 'Game round initiation endpoint',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: true, s: true, e: true }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [{ r: '/api/rounds', m: 'POST', auth: true }],
    telem: [], money: [], auth: true, oban: [], rl: false, flags: [], mod: '2026-02-28',
  },

  round: {
    id: 'round', name: 'GameRound', type: 'resource', domain: 'Game',
    module: 'MyApp.Game.GameRound', sensitive: false, gap: false, cov: 75,
    desc: 'Single game round lifecycle from initiation to settlement. Includes FSM.',
    attrs: [
      { n: 'id', t: 'UUID', d: 'Primary key', pii: false, mon: false, sen: false },
      { n: 'status', t: ':atom', d: 'State machine attribute', pii: false, mon: false, sen: false },
      { n: 'wager', t: 'Money', d: 'Initial wager', pii: false, mon: true, sen: false },
      { n: 'result_amount', t: 'Money', d: 'Settlement amount', pii: false, mon: true, sen: false },
    ],
    actions: [
      { n: 'initiate', c: 'behavioral' }, { n: 'settle', c: 'behavioral' }, { n: 'void', c: 'behavioral' },
    ],
    reqs: [], adrs: ['ADR-002'],
    runbook: null, tests: { p: true, s: true, e: false },
    dl: 'ash_postgres', pt: false, arch: false, pm: false,
    sm: {
      on: true,
      states: [
        { id: 'round-open', name: 'open', marker: 'normal' },
        { id: 'round-settled', name: 'settled', marker: 'active' },
        { id: 'round-void', name: 'void', marker: 'normal' },
      ],
      tr: [
        { f: 'open', t: 'settled', ev: 'settle' },
        { f: 'open', t: 'void', ev: 'void' },
      ],
      attr: 'status',
    },
    routes: [], telem: ['my_app', 'game', 'game_round'],
    money: [
      { n: 'wager', t: 'Money', cldr: 'MyApp.Cldr' },
      { n: 'result_amount', t: 'Money', cldr: 'MyApp.Cldr' },
    ],
    auth: false, oban: [], rl: false,
    flags: [{ n: 'high_stake_mode', adr: 'ADR-013', type: 'other' }], mod: '2026-02-28',
  },

  blueprint: {
    id: 'blueprint', name: 'DepositBonusBlueprint', type: 'blueprint', domain: 'Game',
    module: 'MyApp.Game.DepositBonusBlueprint', sensitive: false, gap: false, cov: 80,
    desc: 'Bonus configuration template with eligibility rules',
    attrs: [], actions: [], reqs: [], adrs: [], runbook: null,
    tests: { p: false, s: true, e: false }, dl: null, pt: false, arch: false, pm: false,
    sm: { on: false, states: [], tr: [], attr: null },
    routes: [], telem: [], money: [], auth: false, oban: [], rl: false, flags: [], mod: '2026-02-20',
  },
};

// ─── Domain ordering ──────────────────────────────────────────────────────────

export const DOMAIN_ORDER = ['Identity', 'Finance', 'Compliance', 'Game'] as const;

// ─── Edges (per spec section 8) ───────────────────────────────────────────────

export const EDGES: GraphEdge[] = [
  // Identity → triggers
  { f: 'input-register', t: 'player', r: 'triggers' },
  { f: 'input-sessions', t: 'player', r: 'triggers' },

  // Player relationships
  { f: 'player', t: 'wallet', r: 'writes' },
  { f: 'player', t: 'limit', r: 'writes' },

  // Finance → triggers
  { f: 'input-withdraw', t: 'withdraw', r: 'triggers' },
  { f: 'input-webhook-pg', t: 'deposit', r: 'triggers' },

  // Withdrawal transfer relationships
  { f: 'withdraw', t: 'wallet', r: 'writes' },
  { f: 'withdraw', t: 'ledger', r: 'writes' },
  { f: 'withdraw', t: 'amlscreen', r: 'async' },

  // Deposit transfer relationships
  { f: 'deposit', t: 'wallet', r: 'writes' },
  { f: 'deposit', t: 'ledger', r: 'writes' },
  { f: 'deposit', t: 'amlscreen', r: 'async' },

  // Provider adapter
  { f: 'withdraw', t: 'pg-adapter', r: 'reads' },
  { f: 'deposit', t: 'pg-adapter', r: 'reads' },

  // Rule guards
  { f: 'kyccheck', t: 'withdraw', r: 'guard' },
  { f: 'rgcheck', t: 'withdraw', r: 'guard' },
  { f: 'rgcheck', t: 'limit', r: 'reads' },

  // AML
  { f: 'input-cron-aml', t: 'amlscreen', r: 'triggers' },
  { f: 'amlscreen', t: 'pg-adapter', r: 'reads' },

  // Game
  { f: 'input-rounds', t: 'round', r: 'triggers' },
  { f: 'round', t: 'wallet', r: 'reads' },

  // Blueprint eligibility
  { f: 'blueprint', t: 'kyccheck', r: 'eligibleIf' },
  { f: 'blueprint', t: 'rgcheck', r: 'eligibleIf' },
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
  // Identity domain (left side, top)
  'input-register':  { x: 40,  y: 40  },
  'input-sessions':  { x: 40,  y: 110 },
  player:            { x: 200, y: 60  },
  wallet:            { x: 200, y: 200 },
  limit:             { x: 40,  y: 260 },
  'player-live':     { x: 40,  y: 340 },

  // Finance domain (center)
  'input-withdraw':  { x: 400, y: 40  },
  'input-webhook-pg':{ x: 400, y: 110 },
  withdraw:          { x: 540, y: 60  },
  deposit:           { x: 540, y: 180 },
  ledger:            { x: 400, y: 260 },
  'pg-adapter':      { x: 400, y: 340 },

  // Compliance domain (right side)
  kyccheck:          { x: 720, y: 60  },
  rgcheck:           { x: 720, y: 140 },
  'input-cron-aml':  { x: 720, y: 220 },
  amlscreen:         { x: 720, y: 300 },

  // Game domain (bottom)
  'input-rounds':    { x: 200, y: 420 },
  round:             { x: 360, y: 420 },
  blueprint:         { x: 540, y: 420 },
};

// ─── Visual constants ─────────────────────────────────────────────────────────

export const NODE_W = 140;
export const NODE_H = 56;

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
