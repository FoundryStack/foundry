'use client';

import { useEffect } from 'react';
import { useStore } from '@/lib/store';
import { getAdrDoc, getRunbookDoc, REQ_META } from '@/lib/data';
import { cn } from '@/lib/utils';

export default function DocPreviewOverlay() {
  const docPreview = useStore((s) => s.docPreview);
  const closeDocPreview = useStore((s) => s.closeDocPreview);

  useEffect(() => {
    if (!docPreview.open) return;
    function handler(e: KeyboardEvent) {
      if (e.key === 'Escape') closeDocPreview();
    }
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [docPreview.open, closeDocPreview]);

  if (!docPreview.open || !docPreview.id) return null;

  const isAdr = docPreview.type === 'adr';
  const isReg = docPreview.type === 'regulation';
  const isRunbook = docPreview.type === 'runbook';

  const adrDoc = isAdr ? getAdrDoc(docPreview.id) : null;
  const reqDoc = isReg ? REQ_META[docPreview.id] ?? null : null;
  const runbookDoc = isRunbook ? getRunbookDoc(docPreview.id) : null;

  return (
    <div
      className={cn(
        'modal modal-middle',
        docPreview.open && 'modal-open'
      )}
      role="dialog"
      aria-modal="true"
      aria-labelledby="doc-preview-title"
    >
      {/* Backdrop — click to close */}
      <div className="modal-backdrop">
        <button
          type="button"
          className="size-full"
          onClick={closeDocPreview}
          aria-label="Close"
        />
      </div>

      {/* Panel — modal-box with custom width */}
      <div
        className="modal-box w-[min(560px,92vw)] max-h-[85vh] flex flex-col p-0"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center gap-2.5 px-4 py-3 border-b border-base-content/10 shrink-0">
          <span
            className={cn(
              'font-mono text-[10px] px-1.5 py-0.5 rounded',
              isAdr && 'badge badge-primary badge-sm',
              isReg && 'badge badge-warning badge-sm',
              isRunbook && 'badge badge-info badge-sm'
            )}
          >
            {docPreview.id}
          </span>
          <span id="doc-preview-title" className="text-sm font-semibold text-base-content flex-1">
            {adrDoc?.title ?? reqDoc?.label ?? runbookDoc?.title ?? docPreview.id}
          </span>
          <button
            type="button"
            onClick={closeDocPreview}
            className="btn btn-ghost btn-sm btn-square text-base-content/50 hover:text-base-content"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-4 text-xs leading-relaxed text-base-content/80">
          {isAdr && adrDoc && (
            <>
              <div className="flex gap-3 mb-3.5 text-[11px] text-base-content/50">
                <span>Status: {adrDoc.status}</span>
                <span>Date: {adrDoc.date}</span>
              </div>
              <div className="mb-3">
                <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                  Summary
                </div>
                <p className="m-0">{adrDoc.summary}</p>
              </div>
              <div className="mb-3">
                <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                  Decision
                </div>
                <p className="m-0">{adrDoc.decision}</p>
              </div>
              {adrDoc.constraints && (
                <div>
                  <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                    Constraints
                  </div>
                  <p className="m-0">{adrDoc.constraints}</p>
                </div>
              )}
            </>
          )}

          {isReg && reqDoc && (
            <>
              <div className="mb-3">
                <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                  Requirement
                </div>
                <p className="m-0 font-medium text-base-content">{reqDoc.label}</p>
              </div>
              {reqDoc.description && (
                <div className="mb-3">
                  <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                    Description
                  </div>
                  <p className="m-0">{reqDoc.description}</p>
                </div>
              )}
              {reqDoc.source && (
                <div>
                  <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                    Source
                  </div>
                  <p className="m-0 font-mono text-[11px] text-base-content/50">
                    {reqDoc.source}
                  </p>
                </div>
              )}
            </>
          )}

          {isRunbook && runbookDoc && (
            <>
              {runbookDoc.whenApplies && (
                <div className="mb-3">
                  <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                    When this runbook applies
                  </div>
                  <p className="m-0">{runbookDoc.whenApplies}</p>
                </div>
              )}
              {runbookDoc.recoverySteps && (
                <div className="mb-3">
                  <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                    Recovery steps
                  </div>
                  <p className="m-0 whitespace-pre-line">{runbookDoc.recoverySteps}</p>
                </div>
              )}
              {runbookDoc.escalation && (
                <div className="mb-3">
                  <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                    Escalation
                  </div>
                  <p className="m-0">{runbookDoc.escalation}</p>
                </div>
              )}
              {runbookDoc.lastTested && (
                <div className="mb-3">
                  <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                    Last tested
                  </div>
                  <p className="m-0">{runbookDoc.lastTested}</p>
                </div>
              )}
              {runbookDoc.complianceNote && (
                <div>
                  <div className="text-[10px] font-semibold tracking-wider uppercase text-base-content/50 mb-1.5">
                    Compliance note
                  </div>
                  <p className="m-0">{runbookDoc.complianceNote}</p>
                </div>
              )}
            </>
          )}

          {((isAdr && !adrDoc) || (isReg && !reqDoc) || (isRunbook && !runbookDoc)) && (
            <p className="text-base-content/50 m-0">Document not found.</p>
          )}
        </div>
      </div>
    </div>
  );
}
