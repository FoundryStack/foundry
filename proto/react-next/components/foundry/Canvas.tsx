'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useStore } from '@/lib/store';
import { NODES, EDGES, NODE_LAYOUT, DOMAIN_ORDER, DOMAIN_FILL, DOMAIN_STROKE, NODE_W, NODE_H } from '@/lib/data';
import { nodeShapePath, covColor, covRgb, escHtml, TYPE_COLOR, TYPE_ABBR } from '@/lib/graph-utils';
import type { GraphNode } from '@/lib/types';
import HoverCard from './HoverCard';

// ─── Legend ──────────────────────────────────────────────────────────────────

const LEGEND: Record<string, Array<{ color: string; label: string; shape?: 'circle' | 'dash' }>> = {
  str: [
    { color: '#2a3050',                  label: 'calls',      shape: 'dash' },
    { color: 'rgba(245,158,11,.5)',      label: 'enforces',   shape: 'dash' },
    { color: 'rgba(167,139,250,.4)',     label: 'triggers',   shape: 'dash' },
    { color: 'rgba(45,212,191,.3)',      label: 'references', shape: 'dash' },
  ],
  cmp: [
    { color: 'rgba(245,158,11,.4)',  label: 'gap' },
    { color: 'rgba(45,212,191,.2)',  label: 'covered' },
    { color: 'var(--s3)',            label: 'no reqs' },
  ],
  sen: [
    { color: 'rgba(248,113,113,.7)', label: 'sensitive',  shape: 'circle' },
    { color: 'var(--s3)',            label: 'standard',   shape: 'circle' },
  ],
  hlth: [
    { color: 'rgba(45,212,191,.4)',  label: '>=80%' },
    { color: 'rgba(245,158,11,.4)',  label: '50-79%' },
    { color: 'rgba(248,113,113,.4)', label: '<50%' },
  ],
  trc: [
    { color: 'var(--yw)',                           label: 'on trace path',   shape: 'circle' },
    { color: 'rgba(245,158,11,.3)',                 label: 'gap on path',     shape: 'circle' },
  ],
  imp: [
    { color: 'rgba(96,165,250,.4)',  label: 'focus module' },
    { color: 'rgba(96,165,250,.2)',  label: 'directly connected' },
    { color: 'var(--s3)',            label: 'no direct link' },
  ],
  erd: [
    { color: 'rgba(167,139,250,.4)', label: 'Resource (has schema)' },
    { color: 'var(--s3)',            label: 'no attributes' },
  ],
};

const LEGEND_TITLE: Record<string, string> = {
  str: 'Edge type', cmp: 'Compliance', sen: 'Sensitive data',
  hlth: 'Test health', trc: 'Scenario trace', imp: 'Impact / Dependency', erd: 'Schema / ERD',
};

// ─── Edge styles ─────────────────────────────────────────────────────────────

const EDGE_STYLE = {
  calls:      { stroke: '#2a3050',              sw: 1.5, dash: '',      marker: 'am-dim' },
  enforces:   { stroke: 'rgba(245,158,11,.35)', sw: 1.5, dash: '4,3',  marker: 'am-yw'  },
  triggers:   { stroke: 'rgba(167,139,250,.3)', sw: 1.5, dash: '2,4',  marker: 'am-pu'  },
  references: { stroke: 'rgba(45,212,191,.22)', sw: 1,   dash: '3,5',  marker: 'am-gn'  },
} as const;

// ─── Node builder ─────────────────────────────────────────────────────────────

function buildNode(
  n: GraphNode,
  pos: { x: number; y: number },
  lens: string,
  isSel: boolean,
  isTrc: boolean,
  isGapTrc: boolean,
  impNode: string | null,
  impSet: Set<string>,
): string {
  const tc = TYPE_COLOR[n.type];
  const covR = n.cov / 100;
  const cc = covColor(n.cov);
  const cr = covRgb(n.cov);

  let op = 1;
  if (lens === 'cmp') op = n.reqs.length ? 1 : 0.22;
  else if (lens === 'sen') op = n.sensitive ? 1 : 0.18;
  else if (lens === 'trc') op = isTrc ? 1 : 0.15;
  else if (lens === 'imp') op = impNode ? (n.id === impNode || impSet.has(n.id) ? 1 : 0.15) : 0.7;
  else if (lens === 'erd') op = n.attrs && n.attrs.length ? 1 : 0.3;

  const filt = isSel ? 'filter="url(#gsel)"' : isTrc && !isSel ? 'filter="url(#gtrc)"' : '';
  const dashAttr = n.gap && lens !== 'trc' ? 'stroke-dasharray="5,3"' : '';

  let strokeC = isSel ? '#9d93ff'
    : isGapTrc ? '#f59e0b'
    : isTrc ? 'rgba(245,158,11,.6)'
    : lens === 'cmp' && n.gap ? 'rgba(245,158,11,.7)'
    : lens === 'sen' && n.sensitive ? 'rgba(248,113,113,.6)'
    : 'rgba(40,40,60,.9)';
  const strokeW = isSel ? 2.5 : isGapTrc || isTrc ? 2 : 1.5;

  let fill = '#111118';
  if (lens === 'hlth') fill = `rgba(${cr},${0.03 + covR * 0.12})`;
  else if (lens === 'cmp') fill = n.gap ? 'rgba(245,158,11,.05)' : n.reqs.length ? 'rgba(45,212,191,.04)' : fill;
  else if (lens === 'imp') {
    if (n.id === impNode) fill = 'rgba(96,165,250,.08)';
    else if (impSet.has(n.id)) fill = 'rgba(96,165,250,.04)';
  } else if (lens === 'erd') fill = n.attrs && n.attrs.length ? 'rgba(167,139,250,.06)' : fill;
  else fill = `rgba(${cr},${0.015 + covR * 0.04})`;

  const { x, y } = pos;
  const shapePath = nodeShapePath(n.type, x, y);
  const covW = Math.round(covR * (NODE_W - 16));

  // Status ring arcs
  const rx = x + NODE_W - 2, ry = y + 2, R = 10;
  const compC = !n.reqs.length ? 'rgba(40,40,60,.6)' : n.gap ? '#f59e0b' : '#2dd4bf';
  const hlthC = covColor(n.cov);
  const opC = n.pm ? '#60a5fa' : n.oban.length ? '#a78bfa' : 'rgba(40,40,60,.6)';
  const a1x1 = rx + R * Math.cos(Math.PI * 1.5), a1y1 = ry + R * Math.sin(Math.PI * 1.5);
  const a1x2 = rx + R * Math.cos(Math.PI * 1.75), a1y2 = ry + R * Math.sin(Math.PI * 1.75);
  const a2x2 = rx + R, a2y2 = ry;
  const a3x2 = rx + R * Math.cos(Math.PI * 0.25), a3y2 = ry + R * Math.sin(Math.PI * 0.25);

  const ring = `
    <path d="M${a1x1},${a1y1} A${R},${R} 0 0,1 ${a1x2},${a1y2}" fill="none" stroke="${compC}" stroke-width="2.5" stroke-linecap="round" opacity="${op}"/>
    <path d="M${a1x2},${a1y2} A${R},${R} 0 0,1 ${a2x2},${a2y2}" fill="none" stroke="${hlthC}" stroke-width="2.5" stroke-linecap="round" opacity="${op}"/>
    <path d="M${a2x2},${a2y2} A${R},${R} 0 0,1 ${a3x2},${a3y2}" fill="none" stroke="${opC}" stroke-width="2.5" stroke-linecap="round" opacity="${op}"/>`;

  const sdot = n.sensitive
    ? `<circle cx="${x + 8}" cy="${y + 8}" r="3.5" fill="rgba(248,113,113,.8)" opacity="${op}"/>`
    : '';
  const typeX = n.sensitive ? x + 18 : x + 10;

  // Infra badges
  let badges = '', bx = x + 8;
  const by = y + NODE_H - 14;
  if (n.oban.length) { badges += `<rect x="${bx}" y="${by}" width="24" height="10" rx="2" fill="rgba(167,139,250,.12)" stroke="rgba(167,139,250,.25)" stroke-width=".7" opacity="${op}"/><text x="${bx + 4}" y="${by + 8}" font-family="Geist Mono,monospace" font-size="6.5" fill="#a78bfa" opacity="${op}">oban</text>`; bx += 28; }
  if (n.sm.on) { badges += `<rect x="${bx}" y="${by}" width="20" height="10" rx="2" fill="rgba(96,165,250,.1)" stroke="rgba(96,165,250,.22)" stroke-width=".7" opacity="${op}"/><text x="${bx + 4}" y="${by + 8}" font-family="Geist Mono,monospace" font-size="6.5" fill="#60a5fa" opacity="${op}">fsm</text>`; bx += 24; }
  if (n.pm) { badges += `<rect x="${bx}" y="${by}" width="30" height="10" rx="2" fill="rgba(96,165,250,.1)" stroke="rgba(96,165,250,.3)" stroke-width=".7" opacity="${op}"/><text x="${bx + 4}" y="${by + 8}" font-family="Geist Mono,monospace" font-size="6.5" fill="#60a5fa" opacity="${op}">migr!</text>`; bx += 34; }
  if (n.rl) { badges += `<rect x="${bx}" y="${by}" width="26" height="10" rx="2" fill="rgba(245,158,11,.08)" stroke="rgba(245,158,11,.2)" stroke-width=".7" opacity="${op}"/><text x="${bx + 4}" y="${by + 8}" font-family="Geist Mono,monospace" font-size="6.5" fill="#f59e0b" opacity="${op}">rate</text>`; }

  const req1 = n.reqs[0]
    ? `<text x="${x + NODE_W - 4}" y="${y + 28}" font-family="Geist Mono,monospace" font-size="7" fill="${n.gap ? 'rgba(245,158,11,.7)' : 'rgba(123,110,246,.6)'}" text-anchor="end" opacity="${op}">${n.reqs[0]}</text>`
    : '';

  const nm = n.name.length > 16 ? n.name.substring(0, 15) + '…' : n.name;
  const stripe = `<rect x="${x}" y="${y}" width="3.5" height="${NODE_H}" rx="1.5" fill="${tc}" opacity="${op * 0.9}"/>`;

  // ERD attribute overlay
  let erdOverlay = '';
  if (lens === 'erd' && n.attrs && n.attrs.length) {
    const erdH = n.attrs.length * 12 + 8;
    const rows = n.attrs.map((a, i) => {
      const ay = y + NODE_H + 4 + i * 12;
      const piiMark = a.pii ? `<tspan fill="#f87171" font-size="7"> PII</tspan>` : '';
      const monMark = a.mon ? `<tspan fill="#f59e0b" font-size="7"> $</tspan>` : '';
      return `<text x="${x + 8}" y="${ay + 9}" font-family="Geist Mono,monospace" font-size="9" fill="${a.pii ? 'rgba(248,113,113,.8)' : a.mon ? 'rgba(245,158,11,.7)' : 'rgba(144,144,170,.75)'}" opacity="${op}">${escHtml(a.n)}${piiMark}${monMark}<tspan fill="rgba(80,80,120,.6)" font-size="8"> : ${escHtml(a.t)}</tspan></text>`;
    }).join('');
    erdOverlay = `
      <rect x="${x}" y="${y + NODE_H}" width="${NODE_W}" height="${erdH}" fill="rgba(8,8,18,.9)" stroke="${strokeC}" stroke-width="${strokeW * 0.7}" opacity="${op}"/>
      <line x1="${x}" y1="${y + NODE_H}" x2="${x + NODE_W}" y2="${y + NODE_H}" stroke="rgba(167,139,250,.3)" stroke-width="1" opacity="${op}"/>
      ${rows}`;
  }

  return `<g data-id="${n.id}" style="cursor:pointer">
    <path d="${shapePath}" fill="${fill}" stroke="${strokeC}" stroke-width="${strokeW}" ${dashAttr} ${filt} opacity="${op}"/>
    ${erdOverlay}
    ${stripe}${sdot}
    <text x="${typeX}" y="${y + 15}" font-family="Geist Mono,monospace" font-size="8" fill="${tc}" font-weight="600" letter-spacing=".05em" opacity="${op}">${TYPE_ABBR[n.type]}</text>
    <text x="${typeX + 16}" y="${y + 15}" font-family="Geist,sans-serif" font-size="11" fill="${isSel || isTrc ? '#e8e8f0' : '#c0c0d8'}" font-weight="${isSel ? '600' : '400'}" opacity="${op}">${nm}</text>
    <rect x="${x + 8}" y="${y + NODE_H - 27}" width="${NODE_W - 16}" height="2" rx="1" fill="rgba(30,30,42,.8)" opacity="${op}"/>
    <rect x="${x + 8}" y="${y + NODE_H - 27}" width="${covW}" height="2" rx="1" fill="${cc}" opacity="${op * 0.9}"/>
    <text x="${x + 8}" y="${y + NODE_H - 30}" font-family="Geist Mono,monospace" font-size="7.5" fill="${cc}" opacity="${op * 0.85}">${n.cov}%</text>
    ${req1}${badges}${ring}
  </g>`;
}

// ─── SVG Defs ─────────────────────────────────────────────────────────────────

const DEFS = `<defs>
  <marker id="am-dim" markerWidth="5" markerHeight="5" refX="4" refY="2.5" orient="auto"><path d="M0,0 L5,2.5 L0,5 z" fill="#2a3050"/></marker>
  <marker id="am-yw" markerWidth="5" markerHeight="5" refX="4" refY="2.5" orient="auto"><path d="M0,0 L5,2.5 L0,5 z" fill="rgba(245,158,11,.8)"/></marker>
  <marker id="am-pu" markerWidth="5" markerHeight="5" refX="4" refY="2.5" orient="auto"><path d="M0,0 L5,2.5 L0,5 z" fill="rgba(167,139,250,.6)"/></marker>
  <marker id="am-gn" markerWidth="5" markerHeight="5" refX="4" refY="2.5" orient="auto"><path d="M0,0 L5,2.5 L0,5 z" fill="rgba(45,212,191,.5)"/></marker>
  <filter id="gsel"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <filter id="gtrc"><feGaussianBlur stdDeviation="4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <filter id="gflow"><feGaussianBlur stdDeviation="2.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>`;

// ─── Canvas component ─────────────────────────────────────────────────────────

export default function Canvas() {
  const lens = useStore((s) => s.lens);
  const selectedId = useStore((s) => s.selectedId);
  const traceSet = useStore((s) => s.traceSet);
  const traceGaps = useStore((s) => s.traceGaps);
  const impNode = useStore((s) => s.impNode);
  const impSet = useStore((s) => s.impSet);
  const selectNode = useStore((s) => s.selectNode);
  const openBottomSheet = useStore((s) => s.openBottomSheet);

  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [hoverPos, setHoverPos] = useState({ x: 0, y: 0 });
  const canvasRef = useRef<HTMLDivElement>(null);
  const hovTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Build SVG markup
  const svgMarkup = useMemo(() => {
    // Domain cluster backgrounds
    const dPts: Record<string, Array<{ x: number; y: number }>> = {};
    Object.values(NODES).forEach((n) => {
      const p = NODE_LAYOUT[n.id];
      if (p) { if (!dPts[n.domain]) dPts[n.domain] = []; dPts[n.domain].push(p); }
    });

    let clusters = '';
    Object.entries(dPts).forEach(([d, pts]) => {
      const xs = pts.map((p) => p.x), ys = pts.map((p) => p.y);
      const x0 = Math.min(...xs) - 14, y0 = Math.min(...ys) - 26;
      const x1 = Math.max(...xs) + NODE_W + 14, y1 = Math.max(...ys) + NODE_H + 14;
      clusters += `<rect x="${x0}" y="${y0}" width="${x1 - x0}" height="${y1 - y0}" rx="10" fill="${DOMAIN_FILL[d] || 'none'}" stroke="${DOMAIN_STROKE[d] || 'rgba(50,50,70,.4)'}" stroke-width="1" stroke-dasharray="5,4"/>
      <text x="${x0 + 8}" y="${y0 + 15}" font-family="Geist Mono,monospace" font-size="8" fill="rgba(100,100,130,.7)" letter-spacing=".12em">${d.toUpperCase()}</text>`;
    });

    // Edges
    let edges = '', flowAnims = '';
    EDGES.forEach((e, ei) => {
      const pa = NODE_LAYOUT[e.f], pb = NODE_LAYOUT[e.t];
      if (!pa || !pb) return;
      const x1 = pa.x + NODE_W, y1 = pa.y + NODE_H / 2;
      const x2 = pb.x, y2 = pb.y + NODE_H / 2;
      const mx = (x1 + x2) / 2;
      const es = EDGE_STYLE[e.r] ?? EDGE_STYLE.calls;
      const isTr = !!(traceSet.has(e.f) && traceSet.has(e.t));
      const dim = lens !== 'str' && !isTr;
      const stroke = isTr ? '#f59e0b' : es.stroke;
      const sw = isTr ? 2.5 : es.sw;
      const dashAttr = isTr ? '' : es.dash ? `stroke-dasharray="${es.dash}"` : '';
      const pathD = `M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`;
      const pid = `ep${ei}`;
      edges += `<path id="${pid}" d="${pathD}" stroke="${stroke}" stroke-width="${sw}" ${dashAttr} fill="none" stroke-opacity="${isTr ? 1 : dim ? 0.18 : 0.75}" marker-end="${isTr ? 'url(#am-yw)' : `url(#${es.marker})`}"/>`;

      if (isTr) {
        const delay = (ei * 0.4) % 2;
        flowAnims += `<circle r="4" fill="#f59e0b" opacity="0.9" filter="url(#gflow)">
          <animateMotion dur="1.8s" begin="${delay}s" repeatCount="indefinite" rotate="auto"><mpath href="#${pid}"/></animateMotion>
          <animate attributeName="opacity" values="0;0.9;0.9;0" keyTimes="0;0.1;0.85;1" dur="1.8s" begin="${delay}s" repeatCount="indefinite"/>
          <animate attributeName="r" values="3;4.5;3" keyTimes="0;0.5;1" dur="1.8s" begin="${delay}s" repeatCount="indefinite"/>
        </circle>`;
      }
    });

    // Nodes
    let nodes = '';
    Object.values(NODES).forEach((n) => {
      const p = NODE_LAYOUT[n.id];
      if (p) {
        nodes += buildNode(
          n, p, lens,
          selectedId === n.id,
          traceSet.has(n.id),
          traceGaps.has(n.id),
          impNode, impSet,
        );
      }
    });

    return DEFS + clusters + edges + flowAnims + nodes;
  }, [lens, selectedId, traceSet, traceGaps, impNode, impSet]);

  // Click delegation on SVG
  const handleSvgClick = useCallback((e: React.MouseEvent<SVGSVGElement>) => {
    const g = (e.target as SVGElement).closest<SVGGElement>('[data-id]');
    if (g) {
      const id = g.dataset.id!;
      selectNode(id);
    }
  }, [selectNode]);

  const handleSvgMouseMove = useCallback((e: React.MouseEvent<SVGSVGElement>) => {
    const g = (e.target as SVGElement).closest<SVGGElement>('[data-id]');
    if (g) {
      const id = g.dataset.id!;
      if (hovTimerRef.current) clearTimeout(hovTimerRef.current);
      const rect = canvasRef.current?.getBoundingClientRect();
      if (rect) {
        let cx = e.clientX - rect.left + 14;
        let cy = e.clientY - rect.top - 10;
        if (cx + 270 > rect.width) cx = e.clientX - rect.left - 274;
        if (cy + 260 > rect.height) cy = rect.height - 265;
        setHoverPos({ x: cx, y: cy });
      }
      setHoveredId(id);
    } else {
      if (hovTimerRef.current) clearTimeout(hovTimerRef.current);
      hovTimerRef.current = setTimeout(() => setHoveredId(null), 80);
    }
  }, []);

  const handleSvgMouseLeave = useCallback(() => {
    if (hovTimerRef.current) clearTimeout(hovTimerRef.current);
    hovTimerRef.current = setTimeout(() => setHoveredId(null), 80);
  }, []);

  const legendItems = LEGEND[lens] ?? LEGEND.str;

  return (
    <div
      ref={canvasRef}
      style={{ flex: 1, position: 'relative', overflow: 'hidden', background: 'var(--bg)' }}
    >
      {/* Grid overlay */}
      <div style={{
        position: 'absolute', inset: 0,
        backgroundImage: 'linear-gradient(rgba(30,30,42,.7) 1px,transparent 1px),linear-gradient(90deg,rgba(30,30,42,.7) 1px,transparent 1px)',
        backgroundSize: '28px 28px', pointerEvents: 'none',
      }} />
      {/* Ambient gradient */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse 55% 45% at 35% 45%,rgba(123,110,246,.035) 0%,transparent 65%),radial-gradient(ellipse 35% 55% at 70% 30%,rgba(45,212,191,.02) 0%,transparent 60%)',
        pointerEvents: 'none',
      }} />

      {/* SVG graph */}
      <svg
        viewBox="-30 -30 830 570"
        style={{ width: '100%', height: '100%', overflow: 'visible', position: 'absolute', top: 0, left: 0 }}
        onClick={handleSvgClick}
        onMouseMove={handleSvgMouseMove}
        onMouseLeave={handleSvgMouseLeave}
        dangerouslySetInnerHTML={{ __html: svgMarkup }}
      />

      {/* Hover card */}
      {hoveredId && (
        <HoverCard
          nodeId={hoveredId}
          lens={lens}
          pos={hoverPos}
        />
      )}

      {/* Fit button */}
      <div style={{ position: 'absolute', top: 10, right: 10 }}>
        <button
          style={{
            padding: '4px 10px', fontSize: 10, background: 'none',
            border: '1px solid var(--b3)', borderRadius: 'var(--r)',
            color: 'var(--t2)', cursor: 'pointer', transition: '.12s',
          }}
          onClick={() => window.dispatchEvent(new Event('resize'))}
        >
          &#10227; Fit
        </button>
      </div>

      {/* Legend */}
      <div style={{
        position: 'absolute', bottom: 12, left: 12,
        background: 'var(--s1)', border: '1px solid var(--b2)',
        borderRadius: 6, padding: '8px 11px', fontSize: 10, color: 'var(--t3)',
        display: 'flex', flexDirection: 'column', gap: 4,
      }}>
        <div style={{ fontSize: 9, fontWeight: 600, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--t3)', marginBottom: 3 }}>
          {LEGEND_TITLE[lens] ?? 'Legend'}
        </div>
        {legendItems.map(({ color, label, shape }) => (
          <div key={label} style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 10 }}>
            <div style={{
              width: 8, height: 8,
              borderRadius: shape === 'circle' ? '50%' : 2,
              background: color,
            }} />
            <span style={{ color: 'var(--t3)' }}>{label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
