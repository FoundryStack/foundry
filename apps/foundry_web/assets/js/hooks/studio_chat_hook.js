export const StudioChatHook = {
  mounted() {
    this._bindFormHandlers()

    this._linkHandler = (event) => {
      const anchor = event.target.closest('[data-role="chat-markdown"] a')
      if (!anchor) return

      const target = this._parseLocalFileTarget(anchor)
      if (!target) return

      event.preventDefault()
      this.pushEvent('fetch_file', target)
    }

    this.el.addEventListener('click', this._linkHandler)
  },

  updated() {
    this._bindFormHandlers()
  },

  destroyed() {
    this._unbindFormHandlers()

    if (this._linkHandler) {
      this.el.removeEventListener('click', this._linkHandler)
    }
  },

  _bindFormHandlers() {
    const nextInput = this.el.querySelector('[data-role="chat-input"]')
    const nextForm = this.el.querySelector('#studio-chat-form')
    this._conversation = this.el.querySelector('#studio-chat-conversation')

    if (this._input === nextInput && this._form === nextForm) return

    this._unbindFormHandlers()
    this._input = nextInput
    this._form = nextForm

    if (!this._input || !this._form) return

    this._keydownHandler = (event) => {
      if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return

      event.preventDefault()
      this._form.requestSubmit()
    }

    this._submitHandler = () => {
      const message = this._input.value.trim()
      if (!message || this._input.disabled) return

      this._appendOptimisticMessage(message)

      requestAnimationFrame(() => {
        if (this._input) {
          this._input.value = ''
          this._input.style.height = ''
        }
      })
    }

    this._input.addEventListener('keydown', this._keydownHandler)
    this._form.addEventListener('submit', this._submitHandler)
  },

  _unbindFormHandlers() {
    if (this._input && this._keydownHandler) {
      this._input.removeEventListener('keydown', this._keydownHandler)
    }

    if (this._form && this._submitHandler) {
      this._form.removeEventListener('submit', this._submitHandler)
    }
  },

  _appendOptimisticMessage(message) {
    if (!this._conversation) return

    const bubble = document.createElement('div')
    bubble.dataset.optimistic = 'true'
    bubble.className = 'flex justify-end'
    bubble.innerHTML = `
      <div class="max-w-[92%] rounded-box border border-primary/25 bg-primary/12 px-4 py-3 text-primary-content/95 shadow-sm">
        <div class="mb-1 flex items-center gap-2">
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">You</p>
        </div>
        <div class="space-y-3 break-words whitespace-pre-wrap text-sm leading-6">${this._escapeHtml(message)}</div>
      </div>
    `

    this._conversation.appendChild(bubble)
    this._conversation.closest('.overflow-y-auto')?.scrollTo({
      top: this._conversation.scrollHeight,
      behavior: 'smooth',
    })
  },

  _parseLocalFileTarget(anchor) {
    const href = anchor.getAttribute('href')
    if (!href || href.startsWith('#')) return null
    if (/^(https?:|mailto:|tel:)/i.test(href)) return null

    const projectRoot = this.el.dataset.projectRoot
    let path = href
    let isAbsolutePath = false

    if (href.startsWith('file://')) {
      path = decodeURIComponent(new URL(href).pathname)
      isAbsolutePath = true
    } else if (href.startsWith('/')) {
      path = decodeURIComponent(href)
      isAbsolutePath = true
    }

    path = decodeURIComponent(path)

    let line = null
    const lineMatch = path.match(/:(\d+)$/)
    if (lineMatch) {
      line = parseInt(lineMatch[1], 10)
      path = path.slice(0, -lineMatch[0].length)
    }

    if (isAbsolutePath) {
      if (!projectRoot) return null
      if (!(path === projectRoot || path.startsWith(`${projectRoot}/`))) return null

      path = path.slice(projectRoot.length).replace(/^\/+/, '')
    }

    if (!path || path === '.' || path === '..') return null

    if (!path.includes('/') && !path.includes('.')) return null

    return line ? { path, line } : { path }
  },

  _escapeHtml(value) {
    const div = document.createElement('div')
    div.textContent = value
    return div.innerHTML
  },
}
