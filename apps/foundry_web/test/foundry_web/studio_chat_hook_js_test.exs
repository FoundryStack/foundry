defmodule FoundryWeb.StudioChatHookJsTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../..", __DIR__)
  @hook_path Path.join(@root, "apps/foundry_web/assets/js/hooks/studio_chat_hook.js")

  test "submit keeps rendering server-driven, clears the composer, and restores focus" do
    result =
      run_js("""
      const hooks = await importBundledModule([#{js_string_literal(@hook_path)}])
      const hook = hooks.StudioChatHook

      class FakeElement {
        constructor(tag = 'div') {
          this.tagName = tag
          this.children = []
          this.listeners = new Map()
          this.dataset = {}
          this.style = {}
          this.disabled = false
          this.value = ''
          this.focusCalls = 0
          this.scrollHeight = 240
          this.clientHeight = 120
          this.scrollTop = 120
          this._innerHTML = ''
        }

        set innerHTML(value) {
          this._innerHTML = value
        }

        get innerHTML() {
          return this._innerHTML
        }

        appendChild(child) {
          child.parentNode = this
          this.children.push(child)
          return child
        }

        addEventListener(type, handler) {
          if (!this.listeners.has(type)) this.listeners.set(type, [])
          this.listeners.get(type).push(handler)
        }

        removeEventListener(type, handler) {
          const handlers = this.listeners.get(type) || []
          this.listeners.set(type, handlers.filter(existing => existing !== handler))
        }

        closest(selector) {
          if (selector === '.overflow-y-auto') return this.scroller || null
          return null
        }

        querySelector(selector) {
          if (selector === '[data-role="chat-input"]') return this.input || null
          if (selector === '#studio-chat-form') return this.form || null
          if (selector === '#studio-chat-conversation') return this.conversation || null
          return null
        }

        requestSubmit() {
          const handlers = this.listeners.get('submit') || []
          handlers.forEach(handler => handler({ preventDefault() {} }))
        }

        focus() {
          this.focusCalls += 1
        }
      }

      const conversation = new FakeElement()
      const scroller = new FakeElement()
      scroller.scrollCalls = []
      scroller.scrollTo = (opts) => scroller.scrollCalls.push(opts)
      conversation.scroller = scroller

      const input = new FakeElement('textarea')
      input.value = 'Ship this fix'
      const form = new FakeElement('form')

      const root = new FakeElement()
      root.input = input
      root.form = form
      root.conversation = conversation
      root.dataset.projectRoot = '/tmp/project'
      root.addEventListener = () => {}
      root.removeEventListener = () => {}

      globalThis.document = {
        createElement: () => new FakeElement(),
      }
      globalThis.requestAnimationFrame = (fn) => fn()
      globalThis.window = {
        location: { search: '' },
      }
      globalThis.localStorage = {
        getItem: () => null,
        setItem: () => {},
      }
      globalThis.URLSearchParams = URLSearchParams

      const state = {
        ...hook,
        el: root,
        pushEvent: () => {},
        handleEvent: () => {},
      }

      hook.mounted.call(state)
      state._autoScrollEnabled = false
      form.requestSubmit()

      printJson({
        bubbles: conversation.children.length,
        autoScrollEnabled: state._autoScrollEnabled,
        scrollCalls: scroller.scrollCalls.length,
        inputValue: input.value,
        focusCalls: input.focusCalls,
      })
      """)

    assert result["bubbles"] == 0
    assert result["autoScrollEnabled"]
    assert result["scrollCalls"] == 0
    assert result["inputValue"] == ""
    assert result["focusCalls"] == 1
  end

  test "auto scroll stays disabled until the user returns to the bottom" do
    result =
      run_js("""
      const hooks = await importBundledModule([#{js_string_literal(@hook_path)}])
      const hook = hooks.StudioChatHook

      const scroller = {
        scrollHeight: 500,
        clientHeight: 200,
        scrollTop: 50,
        calls: [],
        scrollTo(opts) { this.calls.push(opts) },
      }

      const conversation = {
        scrollHeight: 700,
      }

      const state = {
        ...hook,
        _conversation: conversation,
        _conversationScroller: scroller,
        _autoScrollEnabled: false,
      }

      hook._scrollConversationToBottom.call(state, false)
      scroller.scrollTop = 305
      const nearBottom = hook._isNearBottom.call(state)
      state._autoScrollEnabled = nearBottom
      hook._scrollConversationToBottom.call(state, false)

      printJson({
        nearBottom,
        calls: scroller.calls,
      })
      """)

    assert result["nearBottom"]
    assert length(result["calls"]) == 1
    assert hd(result["calls"])["top"] == 700
  end

  test "workspace state hydration prefers stored workspace and syncs on workspace:state" do
    result =
      run_js("""
      const hooks = await importBundledModule([#{js_string_literal(@hook_path)}])
      const hook = hooks.StudioChatHook

      class FakeElement {
        constructor(tag = 'div') {
          this.tagName = tag
          this.children = []
          this.listeners = new Map()
          this.dataset = {}
          this.style = {}
        }

        addEventListener(type, handler) {
          if (!this.listeners.has(type)) this.listeners.set(type, [])
          this.listeners.get(type).push(handler)
        }

        removeEventListener(type, handler) {
          const handlers = this.listeners.get(type) || []
          this.listeners.set(type, handlers.filter(existing => existing !== handler))
        }

        querySelector() {
          return null
        }
      }

      const root = new FakeElement()
      root.dataset.projectRoot = '/tmp/project'

      const pushed = []
      const handled = new Map()
      let saved = null

      globalThis.window = { location: { search: '' } }
      globalThis.URLSearchParams = URLSearchParams
      globalThis.localStorage = {
        getItem: () => JSON.stringify({
          workspace_id: 'workspace-7',
          open_session_ids: ['session-1'],
          active_session_id: 'session-1',
        }),
        setItem: (_key, value) => {
          saved = JSON.parse(value)
        },
      }

      const state = {
        ...hook,
        el: root,
        pushEvent: (event, payload) => pushed.push({ event, payload }),
        handleEvent: (event, callback) => handled.set(event, callback),
      }

      hook.mounted.call(state)
      const workspaceStateHandler = handled.get('workspace:state')
      if (workspaceStateHandler) {
        workspaceStateHandler({
          workspace_id: 'workspace-7',
          open_session_ids: ['session-1', 'session-2'],
          active_session_id: 'session-2',
        })
      }

      printJson({ pushed, saved, handledEvents: Array.from(handled.keys()) })
      """)

    assert result["pushed"] == [
             %{
               "event" => "chat_workspace_hydrate",
               "payload" => %{
                 "workspace_id" => "workspace-7",
                 "open_session_ids" => ["session-1"],
                 "active_session_id" => "session-1"
               }
             }
           ]

    assert result["saved"] == %{
             "workspace_id" => "workspace-7",
             "open_session_ids" => ["session-1", "session-2"],
             "active_session_id" => "session-2"
           }

    assert "workspace:state" in result["handledEvents"]
  end

  defp run_js(source) do
    bootstrap = """
    import { readFile } from 'node:fs/promises'

    const importBundledModule = async (paths) => {
      const parts = []

      for (const path of paths) {
        const source = await readFile(path, 'utf8')
        parts.push(source)
      }

      return import(`data:text/javascript,${encodeURIComponent(parts.join('\\n\\n'))}`)
    }

    const printJson = (value) => console.log(JSON.stringify(value))
    """

    {output, 0} =
      System.cmd(
        "node",
        ["--input-type=module", "-e", bootstrap <> "\n" <> source],
        cd: @root
      )

    output
    |> String.trim()
    |> Jason.decode!()
  end

  defp js_string_literal(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> then(&"'#{&1}'")
  end
end
