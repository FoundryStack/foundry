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
