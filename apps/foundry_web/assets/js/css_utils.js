
// ─────────────────────────────────────────────────────────────────────────────
// CSS → Cytoscape color bridge
//
// Cytoscape renders to Canvas and only accepts rgb()/rgba()/#hex color strings.
// Modern Chrome (v106+) returns getComputedStyle colors in their authored
// format — oklch(), color-mix(), etc. — rather than normalising to rgb().
//
// Strategy:
//   1. Set the CSS variable on a probe <div> and read getComputedStyle.
//   2. If the result is already rgb/rgba, return it directly (fast path).
//   3. Otherwise paint a 1×1 Canvas pixel with that color and read it back
//      via getImageData, which always returns sRGB bytes.
//
// Both the probe element and the canvas are created once and reused on every
// theme change — no DOM or GPU-context churn.
// ─────────────────────────────────────────────────────────────────────────────

export const _probe = (() => {
  const el = document.createElement('div')
  el.style.cssText = 'position:absolute;width:0;height:0;visibility:hidden;pointer-events:none'
  document.documentElement.appendChild(el)
  return el
})()

const _canvas = document.createElement('canvas')
_canvas.width = 1
_canvas.height = 1
const _ctx = _canvas.getContext('2d', { willReadFrequently: true })

function _toRgb(cssColor) {
  _ctx.clearRect(0, 0, 1, 1)
  _ctx.fillStyle = cssColor
  _ctx.fillRect(0, 0, 1, 1)
  const [r, g, b, a] = _ctx.getImageData(0, 0, 1, 1).data
  return a < 255 ? `rgba(${r},${g},${b},${(a / 255).toFixed(3)})` : `rgb(${r},${g},${b})`
}

function _normalize(raw) {
  return raw.startsWith('rgb') ? raw : _toRgb(raw)
}

export function _resolveColor(varName) {
  _probe.style.color = `var(${varName})`
  return _normalize(getComputedStyle(_probe).color)
}

export function _resolveBg(varName) {
  _probe.style.backgroundColor = `var(${varName})`
  return _normalize(getComputedStyle(_probe).backgroundColor)
}
