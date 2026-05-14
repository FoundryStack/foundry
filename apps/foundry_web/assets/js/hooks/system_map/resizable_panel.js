export class ResizablePanel {
  constructor({
    elementId,
    handleId,
    storageKey,
    cssVarName = null,
    defaultWidth,
    minWidth,
    maxWidth,
    deltaSign = 1,
    isOpen = () => true,
    keepWidthWhenClosed = false,
  }) {
    this.elementId = elementId
    this.handleId = handleId
    this.storageKey = storageKey
    this.cssVarName = cssVarName
    this.defaultWidth = defaultWidth
    this.minWidth = minWidth
    this.maxWidth = maxWidth
    this.deltaSign = deltaSign
    this.isOpen = isOpen
    this.keepWidthWhenClosed = keepWidthWhenClosed
    this._width = null
    this._open = null
    this._element = null
    this._handle = null
    this._resizeHandlers = null
  }

  sync({ force = false } = {}) {
    const element = document.getElementById(this.elementId)
    const handle = document.getElementById(this.handleId)

    if (!element || !handle) {
      this.destroy()
      return
    }

    const elementChanged = this._element !== element || this._handle !== handle
    if (elementChanged) {
      this.destroy()
      this._bindResize(element, handle)
    }

    const open = this.isOpen(element)
    const width = this._loadWidth()
    this._setCssWidth(width)

    if (force || elementChanged || this._open !== open || this._width == null) {
      element.style.width = open || this.keepWidthWhenClosed ? `${width}px` : '0px'
    }

    this._element = element
    this._handle = handle
    this._open = open
  }

  destroy() {
    if (!this._resizeHandlers) {
      this._element = null
      this._handle = null
      this._open = null
      return
    }

    const { handle, onMouseDown, onMouseMove, onMouseUp } = this._resizeHandlers
    handle?.removeEventListener('mousedown', onMouseDown)
    document.removeEventListener('mousemove', onMouseMove)
    document.removeEventListener('mouseup', onMouseUp)

    this._resizeHandlers = null
    this._element = null
    this._handle = null
    this._open = null
  }

  _bindResize(element, handle) {
    let isResizing = false
    let startX = 0
    let startWidth = 0

    const onMouseDown = (event) => {
      if (!this.isOpen(element)) return

      isResizing = true
      startX = event.clientX
      startWidth = element.offsetWidth
      element.dataset.resizing = 'true'
      element.style.transition = 'none'
      document.addEventListener('mousemove', onMouseMove)
      document.addEventListener('mouseup', onMouseUp)
      document.body.style.userSelect = 'none'
      document.body.style.cursor = 'col-resize'
      event.preventDefault()
    }

    const onMouseMove = (event) => {
      if (!isResizing) return

      const delta = (event.clientX - startX) * this.deltaSign
      const nextWidth = Math.max(this.minWidth, Math.min(this.maxWidth, startWidth + delta))
      this._width = nextWidth
      this._setCssWidth(nextWidth)
      element.style.width = `${nextWidth}px`
    }

    const onMouseUp = () => {
      if (!isResizing) return

      isResizing = false
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)
      document.body.style.userSelect = ''
      document.body.style.cursor = ''
      delete element.dataset.resizing
      element.style.transition = ''

      this._width = element.offsetWidth
      localStorage.setItem(this.storageKey, String(this._width))
      this._setCssWidth(this._width)
    }

    handle.addEventListener('mousedown', onMouseDown)
    this._resizeHandlers = { handle, onMouseDown, onMouseMove, onMouseUp }
  }

  _loadWidth() {
    if (Number.isFinite(this._width)) return this._width

    const savedWidth = this._readStoredWidth()
    this._width = Number.isFinite(savedWidth) ? savedWidth : this.defaultWidth
    return this._width
  }

  _setCssWidth(width) {
    if (!this.cssVarName || !Number.isFinite(width)) return

    document.documentElement.style.setProperty(this.cssVarName, `${width}px`)
  }

  _readStoredWidth() {
    if (typeof localStorage === 'undefined') return NaN

    return parseInt(localStorage.getItem(this.storageKey), 10)
  }
}
