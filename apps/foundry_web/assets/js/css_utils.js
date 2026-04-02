
// ─────────────────────────────────────────────────────────────────────────────
// CSS → Cytoscape color bridge
//
// Cytoscape renders to Canvas and cannot read CSS variables directly. We
// resolve each --fg-* token to a concrete RGB string by briefly setting it on
// a probe element and reading back getComputedStyle. This handles oklch,
// color-mix, and any other CSS color function the browser supports natively —
// no manual conversion math needed.
// ─────────────────────────────────────────────────────────────────────────────

// Single persistent probe element — created once, reused on every theme change.
export const _probe = (() => {
  const el = document.createElement('div')
  el.style.cssText = 'position:absolute;width:0;height:0;visibility:hidden;pointer-events:none'
  document.documentElement.appendChild(el)
  return el
})()

export function _resolveColor(varName) {
  _probe.style.color = `var(${varName})`
  return getComputedStyle(_probe).color   // browser always returns resolved rgb()
}

export function _resolveBg(varName) {
  _probe.style.backgroundColor = `var(${varName})`
  return getComputedStyle(_probe).backgroundColor
}
