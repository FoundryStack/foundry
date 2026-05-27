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

    this._submitHandler = (e) => {
      const message = this._input.value.trim()
      if (!message) return

      // Add user message to chat immediately on client side
      this._addMessageToChat('user', message)
      // Add thinking bubble to show assistant is responding
      this._addThinkingBubble()

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

  _addThinkingBubble() {
    if (!this._conversation) return

    const wrapper = document.createElement('div')
    wrapper.className = 'flex justify-start'
    wrapper.setAttribute('data-role', 'thinking-bubble')

    const bubble = document.createElement('div')
    bubble.className = 'max-w-[92%] rounded-box border border-base-300 bg-base-200/80 px-4 py-3 text-base-content shadow-sm'

    const header = document.createElement('div')
    header.className = 'mb-1 flex items-center gap-2'
    header.innerHTML = `
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">Assistant</p>
      <span class="text-[10px] uppercase tracking-[0.12em] text-neutral-content/70">Thinking</span>
    `

    const dots = document.createElement('div')
    dots.className = 'foundry-thinking-dots'
    dots.setAttribute('aria-label', 'Assistant is thinking')
    dots.innerHTML = '<span></span><span></span><span></span>'

    bubble.appendChild(header)
    bubble.appendChild(dots)
    wrapper.appendChild(bubble)
    this._conversation.appendChild(wrapper)
    this._scrollConversationToBottom(false)
  },

  _addMessageToChat(role, text) {
    if (!this._conversation) return

    const wrapper = document.createElement('div')
    wrapper.className = role === 'user' ? 'flex justify-end' : 'flex justify-start'

    const bubble = document.createElement('div')
    bubble.className = `max-w-[92%] rounded-box px-4 py-3 text-base-content shadow-sm ${
      role === 'user' ? 'bg-primary/8' : ''
    }`

    const header = document.createElement('div')
    header.className = 'mb-1 flex items-center gap-2'
    header.innerHTML = `<p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-content">${
      role === 'user' ? 'You' : 'Assistant'
    }</p>`

    const content = document.createElement('div')
    content.className = 'space-y-3 break-words leading-6'
    content.textContent = text

    bubble.appendChild(header)
    bubble.appendChild(content)
    wrapper.appendChild(bubble)
    this._conversation.appendChild(wrapper)
    this._scrollConversationToBottom(false)
  },

  _parseLocalFileTarget(anchor) {
    const href = anchor.getAttribute('href')
    if (!href || href.startsWith('#')) return null

    const projectRoot = this.el.dataset.projectRoot
    let path = href
    let isAbsolutePath = false

    if (/^https?:\/\/localhost(:\d+)?\//i.test(href)) {
      const url = new URL(href)
      path = decodeURIComponent(url.pathname)
      if (url.hash && url.hash.startsWith('#L')) {
        path = path + url.hash
      }
      isAbsolutePath = true
    } else if (/^(https?:|mailto:|tel:)/i.test(href)) {
      return null
    } else if (href.startsWith('file://')) {
      path = decodeURIComponent(new URL(href).pathname)
      isAbsolutePath = true
    } else if (href.startsWith('/')) {
      path = decodeURIComponent(href)
      isAbsolutePath = true
    }

    path = decodeURIComponent(path)

    let line = null
    const lineMatch = path.match(/#L(\d+)$/)
    if (lineMatch) {
      line = parseInt(lineMatch[1], 10)
      path = path.slice(0, -lineMatch[0].length)
    } else {
      const colonMatch = path.match(/:(\d+)$/)
      if (colonMatch) {
        line = parseInt(colonMatch[1], 10)
        path = path.slice(0, -colonMatch[0].length)
      }
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
