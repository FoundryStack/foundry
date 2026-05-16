defmodule FoundryWeb.SystemMapHookJsTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../..", __DIR__)
  @hook_path Path.join(@root, "apps/foundry_web/assets/js/hooks/system_map_hook.js")
  @graph_path Path.join(@root, "apps/foundry_web/assets/js/cytoscape_graph.js")
  @drawer_path Path.join(@root, "apps/foundry_web/assets/js/hooks/system_map/drawer_manager.js")
  @sidebar_path Path.join(@root, "apps/foundry_web/assets/js/hooks/system_map/sidebar_manager.js")

  test "switching from coverage back to system map rebinds the sidebar list click handler" do
    result =
      run_js("""
      globalThis.UI_CONFIG = {
        storageKeys: { sidebarWidth: 'sidebar-width' },
        sidebarWidth: { default: 240, min: 160, max: 400 },
        searchDebounce: 0,
      }
      globalThis.ResizablePanel = class {
        sync() {}
        destroy() {}
      }
      globalThis.searchMatch = () => true

      class FakeElement {
        constructor({ id = null, className = '', dataset = {}, attributes = {} } = {}) {
          this.id = id
          this.className = className
          this.dataset = { ...dataset }
          this.attributes = { ...attributes }
          this.children = []
          this.parentNode = null
          this.style = {}
          this.listeners = new Map()
          this.value = ''
        }

        appendChild(child) {
          child.parentNode = this
          this.children.push(child)
          return child
        }

        removeChild(child) {
          const index = this.children.indexOf(child)
          if (index >= 0) {
            this.children.splice(index, 1)
            child.parentNode = null
          }
        }

        addEventListener(type, handler) {
          if (!this.listeners.has(type)) this.listeners.set(type, [])
          this.listeners.get(type).push(handler)
        }

        removeEventListener(type, handler) {
          const handlers = this.listeners.get(type) || []
          this.listeners.set(type, handlers.filter(existing => existing !== handler))
        }

        dispatchEvent(event) {
          const evt = event.target ? event : { ...event, target: this }
          let node = this

          while (node) {
            const handlers = node.listeners.get(evt.type) || []
            handlers.forEach(handler => handler(evt))
            node = node.parentNode
          }
        }

        contains(target) {
          if (target === this) return true
          return this.children.some(child => child.contains(target))
        }

        getAttribute(name) {
          if (name === 'id') return this.id
          if (name === 'class') return this.className
          if (name.startsWith('data-')) {
            const key = name
              .slice(5)
              .replace(/-([a-z])/g, (_, char) => char.toUpperCase())
            return this.dataset[key] ?? null
          }
          return this.attributes[name] ?? null
        }

        closest(selector) {
          if (!selector.startsWith('.')) return null
          const className = selector.slice(1)
          let node = this

          while (node) {
            if (node.className.split(/\\s+/).includes(className)) return node
            node = node.parentNode
          }

          return null
        }

        querySelectorAll(selector) {
          const matches = []
          if (!selector.startsWith('.')) return matches

          const className = selector.slice(1)
          const visit = (node) => {
            if (node.className.split(/\\s+/).includes(className)) {
              matches.push(node)
            }

            node.children.forEach(visit)
          }

          this.children.forEach(visit)
          return matches
        }
      }

      class FakeDocument {
        constructor() {
          this.body = new FakeElement({ id: 'body' })
          this.readyState = 'complete'
        }

        getElementById(id) {
          const visit = (node) => {
            if (node.id === id) return node
            for (const child of node.children) {
              const found = visit(child)
              if (found) return found
            }
            return null
          }

          return visit(this.body)
        }

        querySelector(selector) {
          return this.querySelectorAll(selector)[0] || null
        }

        querySelectorAll(selector) {
          return this.body.querySelectorAll(selector)
        }
      }

      const observers = []
      globalThis.MutationObserver = class {
        constructor(callback) {
          this.callback = callback
          observers.push(this)
        }

        observe(target, options) {
          this.target = target
          this.options = options
        }

        disconnect() {}
      }

      const notifyMutations = () => observers.forEach(observer => observer.callback([]))

      const document = new FakeDocument()
      globalThis.document = document
      globalThis.window = {
        location: { origin: 'http://localhost:4000' },
        open: () => {},
      }

      const metadata = new FakeElement({
        id: 'system-map-metadata',
        dataset: { sidebarTab: 'system_map', selectedNodeId: '' },
      })
      const sidebar = new FakeElement({ id: 'fm-sidebar' })
      document.body.appendChild(metadata)
      document.body.appendChild(sidebar)

      const mountSystemMapList = (nodeIds) => {
        const existingList = document.getElementById('fm-node-list')
        if (existingList) sidebar.removeChild(existingList)

        const list = new FakeElement({ id: 'fm-node-list', className: 'fm-node-list' })
        nodeIds.forEach(nodeId => {
          const button = new FakeElement({
            className: 'fm-node-item',
            dataset: { nodeId, selected: 'false' },
          })
          const label = new FakeElement({ className: 'fm-node-label' })
          button.appendChild(label)
          list.appendChild(button)
        })
        sidebar.appendChild(list)
        return list
      }

      let list = mountSystemMapList(['Alpha'])

      const sidebarModule = await importBundledModule([#{js_string_literal(@sidebar_path)}])
      const hooks = await importBundledModule([#{js_string_literal(@hook_path)}])
      const hook = hooks.SystemMapHook
      const calls = []

      const normalizedNodes = new Map([
        ['Alpha', { id: 'Alpha' }],
        ['Beta', { id: 'Beta' }],
      ])

      const sidebarManager = new sidebarModule.SidebarManager(
        { clearSearch: () => {}, applySearchFilter: () => {} },
        normalizedNodes
      )

      const state = {
        _metadata: hook._metadata,
        _currentSidebarTab: hook._currentSidebarTab,
        _isCoverageMode: hook._isCoverageMode,
        _selectionEventName: hook._selectionEventName,
        _selectNode: hook._selectNode,
        _handleNodeSelected: hook._handleNodeSelected,
        _syncUiState: hook._syncUiState,
        _syncCoverageOverlay: () => {},
        sidebar: sidebarManager,
        drawer: {
          open: () => calls.push('drawer.open'),
          renderForNode: (id) => calls.push(`drawer.render:${id}`),
        },
        graph: {
          normalizedNodes,
          focusNode: (id) => calls.push(`graph.focus:${id}`),
          clearSelection: () => calls.push('graph.clear'),
        },
        pushEvent: (event, payload) => calls.push(`${event}:${payload.id}`),
      }

      sidebarManager.onNodeSelect = (nodeId) => {
        const nodeData = normalizedNodes.get(nodeId)
        hook._selectNode.call(state, nodeId, nodeData, { pushSelection: true })
      }

      hook._startUiObservers.call(state)

      metadata.dataset.sidebarTab = 'test_coverage'
      sidebar.removeChild(list)
      notifyMutations()

      metadata.dataset.sidebarTab = 'system_map'
      list = mountSystemMapList(['Beta'])
      notifyMutations()

      const betaButton = list.children[0]
      const betaLabel = betaButton.children[0]
      betaLabel.dispatchEvent({ type: 'click', target: betaLabel })

      printJson(calls)
      """)

    assert result == [
             "graph.clear",
             "drawer.open",
             "drawer.render:Beta",
             "graph.focus:Beta",
             "node_selected:Beta"
           ]
  end

  test "ui state sync restores graph focus for a persisted system map selection" do
    result =
      run_js("""
      const hooks = await importBundledModule([#{js_string_literal(@hook_path)}])
      const hook = hooks.SystemMapHook
      const calls = []

      const state = {
        _metadata: () => ({
          dataset: {
            sidebarTab: 'system_map',
            selectedNodeId: 'Finance.Wallet',
          },
        }),
        _currentSidebarTab: hook._currentSidebarTab,
        sidebar: {
          hasBoundList: () => true,
          highlightNode: (id) => calls.push(`sidebar.highlight:${id}`),
          clearHighlight: () => calls.push('sidebar.clear'),
        },
        graph: {
          focusNode: (id) => calls.push(`graph.focus:${id}`),
        },
      }

      hook._syncUiState.call(state)
      printJson(calls)
      """)

    assert result == ["sidebar.highlight:Finance.Wallet", "graph.focus:Finance.Wallet"]
  end

  test "preview launch opens canonical target in a browser tab on web" do
    result =
      run_js("""
      const hooks = await importBundledModule([#{js_string_literal(@hook_path)}])
      const hook = hooks.SystemMapHook
      const calls = []

      globalThis.window = {
        location: { origin: 'http://localhost:4000' },
        open: (url, target) => calls.push({ type: 'window.open', url, target }),
      }

      const state = {
        _previewBaseUrl: 'http://localhost:4001',
        _buildPreviewTargetUrl: hook._buildPreviewTargetUrl,
        _normalizePreviewRoute: hook._normalizePreviewRoute,
        _openPreviewLaunch: hook._openPreviewLaunch,
        _isTauriRuntime: hook._isTauriRuntime,
        _openExternalUrl: hook._openExternalUrl,
      }

      await hook._startPreview.call(state, 'games')
      printJson(calls)
      """)

    assert result == [
             %{
               "type" => "window.open",
               "target" => "_blank",
               "url" =>
                 "http://localhost:4000/preview-launch?target=http%3A%2F%2Flocalhost%3A4001%2Fgames"
             }
           ]
  end

  test "preview launch uses the Tauri opener when running in desktop" do
    result =
      run_js("""
      const hooks = await importBundledModule([#{js_string_literal(@hook_path)}])
      const hook = hooks.SystemMapHook
      const calls = []

      globalThis.window = {
        location: { origin: 'http://localhost:4000' },
        open: (url, target) => calls.push({ type: 'window.open', url, target }),
        __TAURI_INTERNALS__: {
          invoke: async (command, payload) => {
            calls.push({ type: 'tauri.invoke', command, payload })
          },
        },
      }

      const state = {
        _previewBaseUrl: 'http://127.0.0.1:4001',
        _buildPreviewTargetUrl: hook._buildPreviewTargetUrl,
        _normalizePreviewRoute: hook._normalizePreviewRoute,
        _openPreviewLaunch: hook._openPreviewLaunch,
        _isTauriRuntime: hook._isTauriRuntime,
        _openExternalUrl: hook._openExternalUrl,
      }

      await hook._startPreview.call(state, '/pages/home')
      printJson(calls)
      """)

    assert result == [
             %{
               "type" => "tauri.invoke",
               "command" => "plugin:opener|open_url",
               "payload" => %{
                 "url" =>
                   "http://localhost:4000/preview-launch?target=http%3A%2F%2F127.0.0.1%3A4001%2Fpages%2Fhome"
               }
             }
           ]
  end

  test "preview route normalization keeps dynamic and empty page routes previewable" do
    result =
      run_js("""
      globalThis.UI_CONFIG = {
        storageKeys: { drawerWidth: 'drawer-width' },
        drawerWidth: { default: 480, min: 320, max: 720 },
      }
      globalThis.ResizablePanel = class {
        sync() {}
      }
      globalThis.document = {
        getElementById: () => null,
      }

      const drawerModule = await importBundledModule([#{js_string_literal(@drawer_path)}])
      const drawer = new drawerModule.DrawerManager(new Map(), () => {})

      printJson({
        dynamic: drawer._previewRouteForNode({ page_route: 'games/:game_id' }),
        empty: drawer._previewRouteForNode({ page_route: '' }),
        missing: drawer._previewRouteForNode({}),
      })
      """)

    assert result == %{
             "dynamic" => "/games/preview",
             "empty" => "/",
             "missing" => "/"
           }
  end

  test "preview launch normalization collapses undefined-like routes to root" do
    result =
      run_js("""
      const hookModule = await importBundledModule([#{js_string_literal(@hook_path)}])
      const hook = hookModule.SystemMapHook

      printJson({
        undefinedString: hook._normalizePreviewRoute('undefined'),
        nullString: hook._normalizePreviewRoute('null'),
        blank: hook._normalizePreviewRoute('   '),
        real: hook._normalizePreviewRoute('games'),
      })
      """)

    assert result == %{
             "undefinedString" => "/",
             "nullString" => "/",
             "blank" => "/",
             "real" => "/games"
           }
  end

  test "focused node keeps only its immediate neighborhood active" do
    result =
      run_js("""
      const graphModule = await importBundledModule([#{js_string_literal(@graph_path)}])
      const graph = Object.create(graphModule.CytoscapeGraph.prototype)

      const makeCollection = (items) => ({
        forEach: (fn) => items.forEach(fn),
        filter: (fn) => makeCollection(items.filter(fn)),
        toArray: () => items.slice(),
        get length() { return items.length },
      })

      const makeNode = (id, parentId = null) => {
        const styleState = {}
        let selected = false

        return {
          length: 1,
          id: () => id,
          parent: () => parentId ? { id: () => parentId } : { id: () => null },
          parents: () => makeCollection(parentId ? [{ id: () => parentId }] : []),
          style: (name, value) => {
            if (value === undefined) return styleState[name]
            styleState[name] = value
          },
          select: () => {
            selected = true
          },
          unselect: () => {
            selected = false
          },
          selected: () => selected,
          styleState,
        }
      }

      const makeEdge = (id, sourceNode, targetNode) => {
        const styleState = {}

        return {
          id: () => id,
          source: () => sourceNode,
          target: () => targetNode,
          data: (key) => key === 'relation' ? 'depends_on' : undefined,
          style: (name, value) => {
            if (value === undefined) return styleState[name]
            styleState[name] = value
          },
          styleState,
        }
      }

      const nodeA = makeNode('A')
      const nodeB = makeNode('B')
      const nodeC = makeNode('C')
      const nodeD = makeNode('D')
      const nodeE = makeNode('E')
      const nodes = [nodeA, nodeB, nodeC, nodeD, nodeE]

      const edgeAB = makeEdge('A->B', nodeA, nodeB)
      const edgeCB = makeEdge('C->B', nodeC, nodeB)
      const edgeDE = makeEdge('D->E', nodeD, nodeE)
      const edges = [edgeAB, edgeCB, edgeDE]

      graph.cy = {
        getElementById: (id) => nodes.find(node => node.id() === id) || { length: 0 },
        elements: () => ({
          unselect: () => nodes.forEach(node => node.unselect()),
        }),
        nodes: () => makeCollection(nodes),
        edges: () => makeCollection(edges),
      }

      graph._hiddenRelations = new Set()
      graph._queueViewportTransition = (fn) => fn()
      graph._centerElementsPreservingZoom = () => {}

      graph.focusNode('B')

      printJson({
        selected: nodeB.selected(),
        nodeOpacity: Object.fromEntries(nodes.map(node => [node.id(), node.styleState.opacity])),
        edgeOpacity: Object.fromEntries(edges.map(edge => [edge.id(), edge.styleState.opacity])),
      })
      """)

    assert result["selected"]
    assert result["nodeOpacity"]["A"] == 1
    assert result["nodeOpacity"]["B"] == 1
    assert result["nodeOpacity"]["C"] == 1
    assert result["nodeOpacity"]["D"] == 0.16
    assert is_nil(result["edgeOpacity"]["A->B"])
    assert is_nil(result["edgeOpacity"]["C->B"])
    assert result["edgeOpacity"]["D->E"] == 0.06
  end

  defp run_js(source) do
    bootstrap = """
    import { readFile } from 'node:fs/promises'

    const importBundledModule = async (paths) => {
      const parts = []

      for (const path of paths) {
        let source = await readFile(path, 'utf8')
        source = source.replace(/^import[\\s\\S]*?from\\s+['\\"][^'\\"]+['\\"]\\s*;?\\n?/gm, '')
        parts.push(source)
      }

      return import(`data:text/javascript,${encodeURIComponent(parts.join('\\n\\n'))}`)
    }

    const printJson = (value) => {
      console.log(JSON.stringify(value))
    }
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
