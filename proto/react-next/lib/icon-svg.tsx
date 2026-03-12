/**
 * Pre-renders Lucide icons to SVG strings for use in Cytoscape HTML templates.
 * Templates expect HTML strings, not React — we use renderToStaticMarkup.
 */

import { renderToStaticMarkup } from 'react-dom/server';
import {
  Hexagon,
  ArrowRightLeft,
  Shield,
  Zap,
  Diamond,
  Play,
  CircleDot,
  Layout,
  LayoutGrid,
  Plug,
  ArrowRight,
  Circle,
  CheckCircle,
  AlertTriangle,
  FileText,
  Archive,
  RefreshCw,
  Lock,
  BookOpen,
  Clock,
  GitBranch,
  Square,
  Database,
} from 'lucide-react';

type IconProps = { size?: number; strokeWidth?: number };

const svg = (Icon: React.ComponentType<IconProps>, size = 14) =>
  renderToStaticMarkup(<Icon size={size} strokeWidth={2} />);

export const TYPE_ICON_SVG: Record<string, string> = {
  resource: svg(Hexagon),
  transfer: svg(ArrowRightLeft),
  rule: svg(Diamond),
  reactor: svg(Diamond),
  job: svg(Zap),
  liveview: svg(Square),
  trigger: svg(Play),
  output: svg(CircleDot),
  blueprint: svg(Layout),
  liveresource: svg(LayoutGrid),
  provider: svg(Plug),
  step: svg(ArrowRight),
  agent: svg(Shield),
  state: svg(Circle),
  cluster: svg(Layout),
};

export const INDICATOR_ICON_SVG: Record<string, string> = {
  covered: svg(CheckCircle, 8),
  gap: svg(AlertTriangle, 8),
  paper_trail: svg(FileText, 8),
  archival: svg(Archive, 8),
  pm: svg(RefreshCw, 8),
  rl: svg(RefreshCw, 8),
  sensitive: svg(Lock, 8),
  runbook: svg(BookOpen, 8),
  oban: svg(Clock, 8),
  fsm: svg(GitBranch, 8),
  adrLinked: svg(FileText, 8),
  policyPresent: svg(Shield, 8),
};

/** PSE icons: P = paper_trail, S = soft delete (archival), E = ecto/Postgres */
export const PSE_ICON_SVG: Record<string, string> = {
  P: svg(FileText, 8),
  S: svg(Archive, 8),
  E: svg(Database, 8),
};

/** Descriptive tooltips for node status indicators */
export const INDICATOR_TITLES: Record<string, string> = {
  covered: 'Compliance covered — all requirements have linked tests',
  gap: 'Compliance gap — one or more requirements untested',
  policyPresent: 'Policy present — node has declared policies or rules',
  sensitive: 'Sensitive resource — requires dual approval for changes',
  paper_trail: 'Paper trail — change history enabled (AshPaperTrail)',
  archival: 'Soft delete — archival enabled (AshArchival)',
  runbook: 'Runbook linked — operational procedure documented',
  adrLinked: 'ADR linked — architecture decision recorded',
  pm: 'Pending migration — unapplied database migration',
  oban: 'Oban queue — background job worker',
  fsm: 'State machine — finite state machine present',
  rl: 'Rate limited — request rate limiting enabled',
};

/** PSE sub-icon tooltips */
export const PSE_TITLES: Record<string, string> = {
  P: 'Paper trail — change history enabled',
  S: 'Soft delete — archival enabled',
  E: 'Ecto/Postgres data layer',
};

/** Type descriptions for node hover legend (from types.ts, ADR-016) */
export const TYPE_DESCRIPTIONS: Record<string, string> = {
  resource: 'Ash.Resource',
  transfer: 'Transfer / Saga',
  rule: 'Rule / Policy',
  reactor: 'Reactor',
  job: 'Oban job',
  liveview: 'Phoenix LiveView',
  trigger: 'Input — API route / Webhook / Scheduler',
  output: 'Terminal — Success / Error / Compensation',
  blueprint: 'Configuration template',
  liveresource: 'Back-office UI (ash_live_resource)',
  provider: 'Provider Adapter — external boundary',
  step: 'Transfer step',
  state: 'FSM state',
  agent: 'Agent step (AshAI)',
  cluster: 'Domain cluster',
};
