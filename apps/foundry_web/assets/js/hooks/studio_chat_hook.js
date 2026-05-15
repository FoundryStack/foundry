export const StudioChatHook = {
  mounted() {
    this._autoScrollEnabled = true
    this._conversation = null
    this._conversationScroller = null
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

    // Restore workspace state from localStorage and hydrate server
    const projectRoot = this.el.dataset.projectRoot || ''
    const storageKey = `foundry_workspace:${projectRoot}`
    let workspaceState = { workspace_id: null, open_session_ids: [], active_session_id: null }

    try {
      const stored = localStorage.getItem(storageKey)
      if (stored) workspaceState = JSON.parse(stored)
    } catch (_e) {}

    // If URL has ?session=<id>, prefer that as the active session
    const urlParams = new URLSearchParams(window.location.search)
    const urlSession = urlParams.get('session')
    if (urlSession) {
      workspaceState.active_session_id = urlSession
      if (!workspaceState.open_session_ids.includes(urlSession)) {
        workspaceState.open_session_ids = [urlSession, ...workspaceState.open_session_ids]
      }
    }

    this.pushEvent('chat_workspace_hydrate', workspaceState)

    // Sync localStorage when server updates workspace state
    this.handleEvent('workspace:state', (state) => {
      try {
        localStorage.setItem(storageKey, JSON.stringify(state))
      } catch (_e) {}
    })

    this.handleEvent('chat:scroll_to_bottom', ({ force = false } = {}) => {
      this._scrollConversationToBottom(force)
    })

    this.handleEvent('copilot:seed_message', ({ message }) => {
      const inputEl = this.el.querySelector('[data-role="chat-input"]')
      if (inputEl) {
        inputEl.value = message
        inputEl.focus()
        inputEl.style.height = 'auto'
        inputEl.style.height = inputEl.scrollHeight + 'px'
      }
    })
  },

  updated() {
    this._bindFormHandlers()
    this._scrollConversationToBottom(false)
  },

  destroyed() {
    this._unbindFormHandlers()
    this._unbindScrollHandler()

    if (this._linkHandler) {
      this.el.removeEventListener('click', this._linkHandler)
    }
  },

  _bindFormHandlers() {
    const nextInput = this.el.querySelector('[data-role="chat-input"]')
    const nextForm = this.el.querySelector('#studio-chat-form')
    const nextConversation = this.el.querySelector('#studio-chat-conversation')

    if (this._conversation !== nextConversation) {
      this._unbindScrollHandler()
      this._conversation = nextConversation
      this._conversationScroller = this._conversation?.closest('.overflow-y-auto') || null
      this._bindScrollHandler()
    }

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
      if (!message) return

      this._autoScrollEnabled = true
      requestAnimationFrame(() => {
        if (!this._input) return

        this._input.value = ''
        this._input.focus()
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

  _bindScrollHandler() {
    if (!this._conversationScroller) return

    this._scrollHandler = () => {
      this._autoScrollEnabled = this._isNearBottom()
    }

    this._conversationScroller.addEventListener('scroll', this._scrollHandler)
    this._autoScrollEnabled = this._isNearBottom()
  },

  _unbindScrollHandler() {
    if (this._conversationScroller && this._scrollHandler) {
      this._conversationScroller.removeEventListener('scroll', this._scrollHandler)
    }

    this._scrollHandler = null
  },

  _scrollConversationToBottom(force = false) {
    if (!this._conversationScroller || !this._conversation) return
    if (!force && !this._autoScrollEnabled) return

    this._conversationScroller.scrollTo({
      top: this._conversation.scrollHeight,
      behavior: force ? 'smooth' : 'auto',
    })
  },

  _isNearBottom() {
    if (!this._conversationScroller) return true

    const threshold = 48
    const remaining =
      this._conversationScroller.scrollHeight -
      this._conversationScroller.clientHeight -
      this._conversationScroller.scrollTop

    return remaining <= threshold
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
}
