import { UI_CONFIG } from '../../graph/config'
import { ResizablePanel } from './resizable_panel'

export class FeedManager {
  constructor() {
    this._panelElement = null
    this._hiddenClass = 'hidden'
    this._openingClasses = ['translate-x-full', 'opacity-0', 'pointer-events-none']
    this._closeDurationMs = 300
    this._isOpen = null

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

    this._clearCloseTimer()

    this._panelElement = null
    this._transitionEndHandler = null
    this._openAnimationFrame = null
    this._isOpen = null
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

        this._finishClose(panel)
      }

      panel.addEventListener('transitionend', this._transitionEndHandler)
      this._panelElement = panel
    }

    const isOpen = panel.dataset.open === 'true'
    const wasOpen = this._isOpen

    if (isOpen) {
      this._clearCloseTimer()
      const wasHidden = panel.classList.contains(this._hiddenClass)
      panel.classList.remove(this._hiddenClass)

      if (wasHidden || forceVisibility || wasOpen === false) {
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

      this._isOpen = true
      return
    }

    if (wasOpen === true) {
      panel.classList.remove(this._hiddenClass)
      this._scheduleClose(panel)
    } else if (wasOpen == null && !forceVisibility) {
      panel.classList.add(this._hiddenClass)
    }

    this._isOpen = false
  }

  _scheduleClose(panel) {
    this._clearCloseTimer()

    this._closeTimer = window.setTimeout(() => {
      this._finishClose(panel)
    }, this._closeDurationMs + 50)
  }

  _finishClose(panel) {
    if (!panel || panel.dataset.open === 'true') return

    this._clearCloseTimer()
    panel.classList.add(this._hiddenClass)
  }

  _clearCloseTimer() {
    if (!this._closeTimer) return

    window.clearTimeout(this._closeTimer)
    this._closeTimer = null
  }
}
