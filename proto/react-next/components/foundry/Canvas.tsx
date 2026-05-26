'use client';

import dynamic from 'next/dynamic';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import cytoscape from 'cytoscape';
import coseBilkent from 'cytoscape-cose-bilkent';
import nodeHtmlLabel from 'cytoscape-node-html-label';
import { useStore } from '@/lib/store';

cytoscape.use(coseBilkent);
nodeHtmlLabel(cytoscape);
import { NODES, EDGES, NODE_LAYOUT, DOMAIN_ORDER, DOMAIN_COLOR, getPrimaryNodeId, getGraphNodeId } from '@/lib/data';
import { edgeStyle, toCytoscapeStylesheet, domainCoverage, covColor, escHtml } from '@/lib/graph-utils';
import { buildCytoscapeElements } from '@/lib/cytoscape-elements';
import { TYPE_ICON_SVG, INDICATOR_ICON_SVG, INDICATOR_TITLES, PSE_ICON_SVG, PSE_TITLES } from '@/lib/icon-svg';
import HoverCard from './HoverCard';

const CytoscapeComponent = dynamic(
  () => import('react-cytoscapejs').then((mod) => mod.default),
  { ssr: false }
);

// ─── Edge legend ─────────────────────────────────────────────────────────────

const EDGE_LEGEND = [
  { r: 'triggers', label: 'triggers' },
  { r: 'writes', label: 'writes' },
  { r: 'reads', label: 'reads' },
  { r: 'guard', label: 'guards' },
  { r: 'async', label: 'async' },
  { r: 'eligibleIf', label: 'eligible-if' },
] as const;

// ─── Canvas component ─────────────────────────────────────────────────────────

export default function Canvas() {
  const selectedId = useStore((s) => s.selectedId);
  const traceSet = useStore((s) => s.traceSet);
  const traceGaps = useStore((s) => s.traceGaps);
  const lens = useStore((s) => s.lens);
  const selectNode = useStore((s) => s.selectNode);

  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [hoverPos, setHoverPos] = useState({ x: 0, y: 0 });
  const canvasRef = useRef<HTMLDivElement>(null);
  const cyRef = useRef<cytoscape.Core | null>(null);

  // Domain coverage for header overlay
  const domainCoverages = useMemo(() => {
    const result: Record<string, number> = {};
    for (const domain of DOMAIN_ORDER) {
      const nodes = Object.values(NODES).filter((n) => n.domain === domain);
      if (nodes.length) {
        const cov = domainCoverage(nodes);
        result[domain] = cov.total;
      }
    }
    return result;
  }, []);

  // Build Cytoscape elements (with compounds for domain clusters, steps, FSM)
  const elements = useMemo(
    () => buildCytoscapeElements(NODES, EDGES, NODE_LAYOUT, { useCompounds: true }),
    []
  );

  // Stylesheet
  const stylesheet = useMemo(
    () => toCytoscapeStylesheet(DOMAIN_COLOR),
    []
  );

  // Layout: preset to use positions from elements directly (skip cose-bilkent physics)
  const layout = useMemo(
    () => ({
      name: 'preset' as const,
      fit: true,
      padding: 55,
    }),
    []
  );

  // Apply trace/selection classes when store changes
  useEffect(() => {
    const cy = cyRef.current;
    if (!cy) return;

    cy.batch(() => {
      // Clear previous
      cy.elements().removeClass('trace trace-gap selected');

      // Apply selection (map entity id to graph node id for compounds)
      if (selectedId) {
        const graphId = getGraphNodeId(selectedId);
        const sel = cy.getElementById(graphId);
        if (sel.length) {
          sel.addClass('selected');
          cy.animate({ center: { eles: sel }, zoom: cy.zoom() }, { duration: 200 });
        }
      }

      // Apply trace
      traceSet.forEach((id) => {
        const graphId = getGraphNodeId(id);
        const el = cy.getElementById(graphId);
        if (el.length) el.addClass(traceGaps.has(id) ? 'trace-gap' : 'trace');
      });
    });
  }, [selectedId, traceSet, traceGaps]);

  const handleCyRef = useCallback((cy: cytoscape.Core | undefined) => {
    if (cy) {
      cyRef.current = cy;
      type CyExt = cytoscape.Core & {
        _foundryHandlers?: boolean;
        _foundryLabelsSetup?: boolean;
        nodeHtmlLabel?: (p: unknown[], o?: { enablePointerEvents?: boolean }) => cytoscape.Core;
      };
      const cyExt = cy as CyExt;
      // Register handlers once; cy() runs on every update, avoid re-registering
      if (!cyExt._foundryHandlers) {
        cyExt._foundryHandlers = true;
        cy.on('tap', 'node', (evt: cytoscape.EventObject) => {
          const id = evt.target.data('id');
          if (id) {
            const primaryId = getPrimaryNodeId(id) ?? id;
            selectNode(primaryId);
          }
        });
        cy.on('mouseover', 'node', (evt: cytoscape.EventObject) => {
          const id = evt.target.data('id');
          if (!id) return;
          setHoveredId(id);
          const orig = evt.originalEvent as MouseEvent;
          const container = cy.container();
          if (container && orig) {
            const rect = container.getBoundingClientRect();
            let cx = orig.clientX - rect.left + 14;
            let cy2 = orig.clientY - rect.top - 10;
            if (cx + 280 > rect.width) cx = orig.clientX - rect.left - 290;
            if (cy2 + 300 > rect.height) cy2 = rect.height - 310;
            setHoverPos({ x: cx, y: Math.max(10, cy2) });
          }
        });
        cy.on('mouseout', 'node', () => {
          setHoveredId(null);
        });
      }
      // HTML labels for rich node content — setup once; re-calling nodeHtmlLabel
      // causes removeChild errors when the extension tries to clean up stale DOM
      if (!cyExt._foundryLabelsSetup && cyExt.nodeHtmlLabel) {
        cyExt._foundryLabelsSetup = true;
        const entityTpl = (data: Record<string, unknown>) => {
          const name = (data.name ?? data.label ?? '') as string;
          const type = (data.type ?? 'resource') as string;
          const typeColor = (data.typeColor ?? '#9090b0') as string;
          const reqs = (data.reqs as string[] | undefined) ?? [];
          const nodeKind = (data.nodeKind ?? 'entity') as string;
          const indicators = (data.indicators ?? {}) as Record<string, boolean | undefined>;
          const isSm = nodeKind === 'step' || nodeKind === 'state' || nodeKind === 'output';
          const typeIconSvg = type === 'agent' ? '' : (TYPE_ICON_SVG[type] ?? TYPE_ICON_SVG.resource);
          const agentIcon = type === 'agent' ? '<span style="font-size:14px;font-weight:600;color:var(--pu)">⊕</span>' : '';
          const indicatorMap: Record<string, string> = { pt: 'paper_trail', arch: 'archival', sm: 'fsm', adrLinked: 'adrLinked', policyPresent: 'policyPresent' };
          const indicatorOrder = ['covered', 'gap', 'policyPresent', 'sensitive', 'pt', 'arch', 'runbook', 'adrLinked', 'pm', 'oban', 'sm', 'rl'] as const;
          const pse = (indicators.pse as string | undefined);
          const activeIndicators = indicatorOrder.filter((k) => indicators[k]).slice(0, 5);
          const indicatorSvgs = activeIndicators
            .map((k) => {
              const iconKey = indicatorMap[k] ?? k;
              const svg = INDICATOR_ICON_SVG[iconKey];
              const title = INDICATOR_TITLES[iconKey] ?? k;
              return svg ? `<span data-indicator="${iconKey}" title="${escHtml(title)}">${svg}</span>` : '';
            })
            .filter(Boolean)
            .join('');
          const smClass = isSm ? ' cy-node-sm' : '';
          const typeBadge = `<span class="req-badge type-badge" style="color:${escHtml(typeColor)};border-color:${escHtml(typeColor)}40">${escHtml(type)}</span>`;
          const reqBadgeHtml = reqs.slice(0, 4).map((r) => `<span class="req-badge">${escHtml(r)}</span>`).join('');
          const pseSpan = pse ? pse.split('').map((ch) => {
            const icon = PSE_ICON_SVG[ch];
            const title = PSE_TITLES[ch];
            return icon && title ? `<span data-indicator="pse-${ch}" title="${escHtml(title)}">${icon}</span>` : '';
          }).filter(Boolean).join('') : '';
          const reqBadges = !isSm
            ? `<div class="req-badges">${typeBadge}${reqBadgeHtml}</div>`
            : '';
          return `<div class="cy-node-html${smClass}">
          <div class="status-icons">${indicatorSvgs}${pseSpan}</div>
          <div class="title-row">
            ${agentIcon || `<span class="type-icon" style="color:${escHtml(typeColor)}">${typeIconSvg}</span>`}
            <span class="title" style="color:${escHtml(typeColor)}">${escHtml(name)}</span>
          </div>
          ${reqBadges}
        </div>`;
        };
        const boundaryTpl = (data: Record<string, unknown>) => {
          const name = (data.name ?? data.label ?? '') as string;
          const type = (data.type ?? 'cluster') as string;
          const typeColor = (data.typeColor ?? '#9090b0') as string;
          const typeIconSvg = TYPE_ICON_SVG[type] ?? TYPE_ICON_SVG.cluster;
          return `<div class="cy-node-html cy-node-boundary">
          <div class="title-row">
            <span class="type-icon" style="color:${escHtml(typeColor)}">${typeIconSvg}</span>
            <span class="title" style="color:${escHtml(typeColor)}">${escHtml(name)}</span>
          </div>
        </div>`;
        };
        cyExt.nodeHtmlLabel(
          [
            {
              query: 'node[nodeKind="entity"], node[nodeKind="step"], node[nodeKind="state"], node[nodeKind="output"]',
              halign: 'center',
              valign: 'center',
              halignBox: 'center',
              valignBox: 'center',
              tpl: entityTpl,
            },
            {
              query: 'node[nodeKind="cluster"]',
              halign: 'left',
              valign: 'top',
              halignBox: 'right',
              valignBox: 'bottom',
              tpl: boundaryTpl,
            },
          ],
          { enablePointerEvents: false }
        );
      }
    } else {
      cyRef.current = null;
    }
  }, [selectNode]);

  return (
    <div
      ref={canvasRef}
      style={{ flex: 1, position: 'relative', overflow: 'hidden', background: 'var(--bg)' }}
    >
      {/* Grid overlay */}
      <div style={{
        position: 'absolute', inset: 0,
        backgroundImage: 'linear-gradient(rgba(40,40,60,.4) 1px,transparent 1px),linear-gradient(90deg,rgba(40,40,60,.4) 1px,transparent 1px)',
        backgroundSize: '24px 24px', pointerEvents: 'none',
      }} />

      {/* Ambient gradient */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse 50% 40% at 30% 40%,rgba(123,110,246,.03) 0%,transparent 60%),radial-gradient(ellipse 40% 50% at 70% 30%,rgba(52,211,153,.02) 0%,transparent 55%)',
        pointerEvents: 'none',
      }} />

      {/* Cytoscape graph */}
      <div style={{ position: 'absolute', inset: 0 }}>
        <CytoscapeComponent
          elements={elements}
          style={{ width: '100%', height: '100%' }}
          stylesheet={stylesheet}
          layout={layout}
          cy={(cy) => handleCyRef(cy)}
        />
      </div>

      {/* Hover card */}
      {hoveredId && (
        <HoverCard nodeId={hoveredId} lens={lens} pos={hoverPos} />
      )}

      {/* Domain coverage header */}
      <div style={{
        position: 'absolute', top: 12, left: '50%', transform: 'translateX(-50%)',
        display: 'flex', alignItems: 'center', gap: 16,
        background: 'rgba(13,13,22,.9)', border: '1px solid rgba(70,70,100,.4)',
        borderRadius: 6, padding: '6px 14px', fontSize: 10,
        pointerEvents: 'none', zIndex: 10,
      }}>
        {DOMAIN_ORDER.map((domain) => {
          const cov = domainCoverages[domain] ?? 0;
          return (
            <div key={domain} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ fontFamily: 'var(--font-mono)', fontWeight: 600, color: DOMAIN_COLOR[domain], fontSize: 9 }}>
                {domain.toUpperCase()}
              </span>
              <div style={{ width: 40, height: 4, background: 'rgba(50,50,70,.6)', borderRadius: 2, overflow: 'hidden' }}>
                <div style={{ width: `${cov}%`, height: '100%', background: covColor(cov), borderRadius: 2 }} />
              </div>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: covColor(cov), minWidth: 28 }}>{cov}%</span>
            </div>
          );
        })}
      </div>

      {/* Edge legend */}
      <div style={{
        position: 'absolute', bottom: 12, left: 12,
        background: 'rgba(13,13,22,.9)', border: '1px solid rgba(70,70,100,.4)',
        borderRadius: 6, padding: '8px 12px', fontSize: 10,
        display: 'flex', flexDirection: 'column', gap: 4,
      }}>
        <div style={{ fontSize: 8, fontWeight: 600, letterSpacing: '.1em', textTransform: 'uppercase', color: 'rgba(144,144,180,.7)', marginBottom: 2 }}>
          Edge Types
        </div>
        {EDGE_LEGEND.map(({ r, label }) => {
          const es = edgeStyle(r as Parameters<typeof edgeStyle>[0]);
          return (
            <div key={r} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <svg width="24" height="8" style={{ overflow: 'visible' }}>
                <line x1="0" y1="4" x2="24" y2="4" stroke={es.stroke} strokeWidth={es.sw} strokeDasharray={es.dash || undefined} />
              </svg>
              <span style={{ color: 'rgba(180,180,200,.7)' }}>{label}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
