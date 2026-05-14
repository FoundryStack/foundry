import { UI_CONFIG } from '../../graph/config'
import { ResizablePanel } from './resizable_panel'

export class FeedManager {
  constructor() {
    this._panelElement = null
    this._hiddenClass = 'hidden'
    this._openingClasses = ['translate-x-full', 'opacity-0', 'pointer-events-none']

    this._panel = new ResizablePanel({
      elementId: 'fm-feed',
      handleId: 'feed-resize-handle',
      storageKey: UI_CONFIG.storageKeys.feedWidth,
      cssVarName: '--foundry-feed-width',
      defaultWidth: UI_CONFIG.feedWidth.default,
      minWidth: UI_CONFIG.feedWidth.min,
      maxWidth: UI_CONFIG.feedWidth.max,
      deltaSign: -1,
      isOpen: (feed) => feed.dataset.open === 'true',
      keepWidthWhenClosed: true,
    })

    this._panel.sync({ force: true })
    this.sync({ forceVisibility: true })
  }

  sync({ forceVisibility = false } = {}) {
    this._panel.sync()
    this._syncVisibility(forceVisibility)
  }

  destroy() {
    if (this._panelElement && this._transitionEndHandler) {
      this._panelElement.removeEventListener('transitionend', this._transitionEndHandler)
    }

    if (this._openAnimationFrame) {
      cancelAnimationFrame(this._openAnimationFrame)
    }

    this._panelElement = null
    this._transitionEndHandler = null
    this._openAnimationFrame = null
    this._panel.destroy()
  }

  _syncVisibility(forceVisibility) {
    const panel = document.getElementById('fm-feed')
    if (!panel) return

    if (this._panelElement !== panel) {
      if (this._panelElement && this._transitionEndHandler) {
        this._panelElement.removeEventListener('transitionend', this._transitionEndHandler)
      }

      this._transitionEndHandler = (event) => {
        if (event.target !== panel || event.propertyName !== 'transform') return
        if (panel.dataset.open === 'true') return

        panel.classList.add(this._hiddenClass)
      }

      panel.addEventListener('transitionend', this._transitionEndHandler)
      this._panelElement = panel
    }

    const isOpen = panel.dataset.open === 'true'

    if (isOpen) {
      const wasHidden = panel.classList.contains(this._hiddenClass)
      panel.classList.remove(this._hiddenClass)

      if (wasHidden || forceVisibility) {
        panel.classList.add(...this._openingClasses)
        panel.getBoundingClientRect()

        if (this._openAnimationFrame) {
          cancelAnimationFrame(this._openAnimationFrame)
        }

        this._openAnimationFrame = requestAnimationFrame(() => {
          panel.classList.remove(...this._openingClasses)
          this._openAnimationFrame = null
        })
      }

      return
    }

    panel.classList.remove(this._hiddenClass)
  }
}
