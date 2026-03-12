import React from 'react';
import type { Lens } from './types';
import type { ResolvedNode } from './data';
import type { Attribute } from './types';

type HoverExtraRenderer = (node: ResolvedNode) => React.ReactNode;

const ROW_STYLE = { height: 1, background: 'var(--b2)', margin: '5px 0' } as const;

function renderAuthHint(): React.ReactNode {
  return (
    <>
      <div style={ROW_STYLE} />
      <div style={{ fontSize: 10, color: 'var(--t3)' }}>Actor / action matrix — see Authorization tab</div>
    </>
  );
}

function renderAttrs(node: ResolvedNode): React.ReactNode {
  const attrs = 'attrs' in node ? (node.attrs as Attribute[]) : [];
  if (!attrs.length) return null;
  return (
    <>
      <div style={ROW_STYLE} />
      {attrs.slice(0, 5).map((a) => (
        <div key={a.n} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>{a.n}</span>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--pu)' }}>{a.t}</span>
          {a.pii && <span style={{ fontSize: 7, color: 'var(--rd)', marginLeft: 2 }}>PII</span>}
          {a.mon && <span style={{ fontSize: 7, color: 'var(--yw)', marginLeft: 2 }}>$</span>}
        </div>
      ))}
      {attrs.length > 5 && (
        <div style={{ fontSize: 9, color: 'var(--t3)', padding: '2px 0' }}>+{attrs.length - 5} more…</div>
      )}
    </>
  );
}

function renderResourceAttrs(node: ResolvedNode): React.ReactNode {
  const attrs = 'attrs' in node ? (node.attrs as Attribute[]) : [];
  if (!attrs.length) return null;
  return (
    <>
      <div style={ROW_STYLE} />
      {attrs.slice(0, 3).map((a) => (
        <div key={a.n} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>{a.n}</span>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--bl)' }}>{a.t}</span>
          {a.sen && <span style={{ fontSize: 7, color: 'var(--rd)', marginLeft: 4 }}>PII</span>}
        </div>
      ))}
    </>
  );
}

function renderTransferSteps(node: ResolvedNode): React.ReactNode {
  const actions = 'actions' in node ? node.actions : [];
  const count = Array.isArray(actions) ? actions.length : 0;
  return (
    <>
      <div style={ROW_STYLE} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>steps</span>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--ac2)' }}>{count} actions</span>
      </div>
    </>
  );
}

function renderRuleReqs(node: ResolvedNode): React.ReactNode {
  const reqs = node.reqs ?? [];
  const count = reqs.length;
  return (
    <>
      <div style={ROW_STYLE} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10 }}>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--t3)', width: 66 }}>enforces</span>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--yw)' }}>
          {count} req{count !== 1 ? 's' : ''}
        </span>
      </div>
    </>
  );
}

const RENDERERS: Array<{
  match: (lens: Lens, node: ResolvedNode) => boolean;
  render: HoverExtraRenderer;
}> = [
  { match: (l, n) => l === 'auth' && n.type === 'resource', render: renderAuthHint },
  { match: (l, n) => l === 'cfg' && 'attrs' in n && (n.attrs as unknown[]).length > 0, render: renderAttrs },
  {
    match: (l, n) =>
      (l === 'default' || l === 'trc') && n.type === 'resource' && 'attrs' in n && (n.attrs as unknown[]).length > 0,
    render: renderResourceAttrs,
  },
  {
    match: (l, n) =>
      (l === 'default' || l === 'trc') && (n.type === 'transfer' || n.type === 'reactor'),
    render: renderTransferSteps,
  },
  { match: (l, n) => (l === 'default' || l === 'trc') && n.type === 'rule', render: renderRuleReqs },
];

export function getHoverExtraRows(lens: Lens, node: ResolvedNode): React.ReactNode {
  const r = RENDERERS.find((x) => x.match(lens, node));
  return r ? r.render(node) : null;
}
