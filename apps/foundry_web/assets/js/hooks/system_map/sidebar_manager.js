import { searchMatch } from '../../foundry_graph'
import { UI_CONFIG } from '../../graph/config'

const SELECTORS = {
  sidebarList: 'fm-sidebar-list',
  search: 'fm-search',
}

export class SidebarManager {
  constructor(graph, normalizedNodes) {
    this.graph = graph
    this.normalizedNodes = normalizedNodes
    this._initSidebar()
    this._initSearch()
    this._initResize()
  }

  _initSidebar() {
    const list = document.getElementById(SELECTORS.sidebarList)
    if (!list) return

    this._sidebarClickHandler = (evt) => {
      const item = evt.target.closest('[data-node-id]')
      if (item) {
        const nodeId = item.dataset.nodeId
        this.highlightNode(nodeId)
        this.graph.selectNode(nodeId)
        this.graph.centerOn(nodeId)
      }
    }
    list.addEventListener('click', this._sidebarClickHandler)
  }

  highlightNode(nodeId) {
    const list = document.getElementById(SELECTORS.sidebarList)
    if (list) {
      list.querySelectorAll('[data-node-id]').forEach(item => {
        item.classList.toggle('active', item.dataset.nodeId === nodeId)
      })
    }
  }

  _initSearch() {
    const searchInput = document.getElementById(SELECTORS.search)
    if (!searchInput) return

    this._searchInputHandler = (evt) => {
      clearTimeout(this._searchTimeout)
      const query = evt.target.value.trim()

      this._searchTimeout = setTimeout(() => {
        const list = document.getElementById(SELECTORS.sidebarList)
        if (!list) return

        const items = list.querySelectorAll('[data-node-id]')
        items.forEach(item => {
          const nodeId = item.dataset.nodeId
          const node = this.normalizedNodes.get(nodeId)

          if (!node) {
            item.style.display = 'none'
            return
          }

          const match = searchMatch(node, query)
          item.style.display = match ? '' : 'none'
        })
      }, UI_CONFIG.searchDebounce)
    }
    searchInput.addEventListener('input', this._searchInputHandler)
  }

  _initResize() {
    const layout = document.querySelector('.foundry-map-layout')
    const sidebar = document.getElementById('foundry-sidebar')
    const handle = document.getElementById('sidebar-resize-handle')

    if (!sidebar || !handle || !layout) return

    const savedWidth = localStorage.getItem(UI_CONFIG.storageKeys.sidebarWidth)
    const initialWidth = savedWidth ? parseInt(savedWidth, 10) : UI_CONFIG.sidebarWidth.default
    layout.style.gridTemplateColumns = `${initialWidth}px 1fr`

    let isResizing = false
    let startX = 0
    let startWidth = 0

    const onMouseDown = (e) => {
      isResizing = true
      startX = e.clientX
      startWidth = sidebar.offsetWidth
      document.addEventListener('mousemove', onMouseMove)
      document.addEventListener('mouseup', onMouseUp)
      document.body.style.userSelect = 'none'
      document.body.style.cursor = 'col-resize'
      e.preventDefault()
    }

    const onMouseMove = (e) => {
      if (!isResizing) return
      const delta = e.clientX - startX
      const newWidth = Math.max(UI_CONFIG.sidebarWidth.min, Math.min(UI_CONFIG.sidebarWidth.max, startWidth + delta))
      layout.style.gridTemplateColumns = `${newWidth}px 1fr`
    }

    const onMouseUp = () => {
      isResizing = false
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)
      document.body.style.userSelect = ''
      document.body.style.cursor = ''
      localStorage.setItem(UI_CONFIG.storageKeys.sidebarWidth, sidebar.offsetWidth)
    }

    handle.addEventListener('mousedown', onMouseDown)
    this._resizeHandlers = { onMouseDown, onMouseMove, onMouseUp, handle }
  }

  destroy() {
    const list = document.getElementById(SELECTORS.sidebarList)
    if (list && this._sidebarClickHandler) {
      list.removeEventListener('click', this._sidebarClickHandler)
    }

    const searchInput = document.getElementById(SELECTORS.search)
    if (searchInput && this._searchInputHandler) {
      searchInput.removeEventListener('input', this._searchInputHandler)
      clearTimeout(this._searchTimeout)
    }

    if (this._resizeHandlers) {
      const { onMouseDown, handle } = this._resizeHandlers
      if (handle && onMouseDown) {
        handle.removeEventListener('mousedown', onMouseDown)
      }
    }
  }
}
