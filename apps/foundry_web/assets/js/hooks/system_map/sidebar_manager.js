import { searchMatch } from '../../foundry_graph'
import { UI_CONFIG } from '../../graph/config'
import { ResizablePanel } from './resizable_panel'

const SELECTORS = {
  sidebarList: 'fm-node-list',
  nodeItem: 'fm-node-item',
  search: 'fm-sidebar-search',
  nodeItemAttr: 'data-node-id',
}

export class SidebarManager {
  constructor(graph, normalizedNodes) {
    this.graph = graph
    this.normalizedNodes = normalizedNodes
    this.onNodeSelect = null
    this.onFilter = null
    this._panel = new ResizablePanel({
      elementId: 'fm-sidebar',
      handleId: 'sidebar-resize-handle',
      storageKey: UI_CONFIG.storageKeys.sidebarWidth,
      cssVarName: '--foundry-sidebar-width',
      defaultWidth: UI_CONFIG.sidebarWidth.default,
      minWidth: UI_CONFIG.sidebarWidth.min,
      maxWidth: UI_CONFIG.sidebarWidth.max,
    })
    this._initSidebar()
    this._initSearch()
    this._panel.sync({ force: true })
  }

  _initSidebar() {
    const list = document.getElementById(SELECTORS.sidebarList)
    if (!list || this._boundList === list) return

    if (this._boundList && this._sidebarClickHandler) {
      this._boundList.removeEventListener('click', this._sidebarClickHandler)
    }

    this._sidebarClickHandler = (evt) => {
      const item = evt.target.closest(`.${SELECTORS.nodeItem}`)
      if (item) {
        const nodeId = item.getAttribute(SELECTORS.nodeItemAttr)
        if (nodeId) {
          this.onNodeSelect?.(nodeId)
        }
      }
    }
    list.addEventListener('click', this._sidebarClickHandler)
    this._boundList = list
  }

  highlightNode(nodeId) {
    const list = document.getElementById(SELECTORS.sidebarList)
    if (list) {
      list.querySelectorAll(`.${SELECTORS.nodeItem}`).forEach(item => {
        const itemId = item.getAttribute(SELECTORS.nodeItemAttr)
        item.dataset.selected = itemId === nodeId ? 'true' : 'false'
      })
    }
  }

  clearHighlight() {
    const list = document.getElementById(SELECTORS.sidebarList)
    if (list) {
      list.querySelectorAll(`.${SELECTORS.nodeItem}`).forEach(item => {
        item.dataset.selected = 'false'
      })
    }
  }

  _initSearch() {
    const searchInput = document.querySelector(`.${SELECTORS.search}`)
    if (!searchInput || this._boundSearchInput === searchInput) return

    if (this._boundSearchInput && this._searchInputHandler) {
      this._boundSearchInput.removeEventListener('input', this._searchInputHandler)
    }

    this._searchInputHandler = (evt) => {
      clearTimeout(this._searchTimeout)
      const query = evt.target.value.trim()

      this._searchTimeout = setTimeout(() => {
        this._applySearch(query)
      }, UI_CONFIG.searchDebounce)
    }
    searchInput.addEventListener('input', this._searchInputHandler)
    this._boundSearchInput = searchInput
    this._applySearch(searchInput.value.trim())
  }

  sync() {
    this._initSidebar()
    this._initSearch()
    this._panel.sync()
  }

  hasBoundList() {
    return !!this._boundList && document.body.contains(this._boundList)
  }

  destroy() {
    if (this._boundList && this._sidebarClickHandler) {
      this._boundList.removeEventListener('click', this._sidebarClickHandler)
    }

    if (this._boundSearchInput && this._searchInputHandler) {
      this._boundSearchInput.removeEventListener('input', this._searchInputHandler)
      clearTimeout(this._searchTimeout)
    }

    this._boundList = null
    this._boundSearchInput = null
    this._panel.destroy()
  }

  _applySearch(query) {
    const list = document.getElementById(SELECTORS.sidebarList)
    if (!list) return

    const items = list.querySelectorAll(`.${SELECTORS.nodeItem}`)
    const matchingIds = new Set()

    items.forEach(item => {
      const nodeId = item.getAttribute(SELECTORS.nodeItemAttr)
      const node = this.normalizedNodes.get(nodeId)

      if (!node) {
        item.style.display = 'none'
        return
      }

      const match = searchMatch(node, query)
      item.style.display = match ? '' : 'none'
      if (match) matchingIds.add(nodeId)
    })

    list.querySelectorAll('.fm-domain-group').forEach(group => {
      let sibling = group.nextElementSibling
      let hasVisibleItems = false

      while (sibling && !sibling.classList.contains('fm-domain-group')) {
        if (sibling.classList.contains(SELECTORS.nodeItem) && sibling.style.display !== 'none') {
          hasVisibleItems = true
          break
        }
        sibling = sibling.nextElementSibling
      }

      group.style.display = hasVisibleItems || query === '' ? '' : 'none'
    })

    if (query === '') {
      this.graph.clearSearch()
    } else {
      this.graph.applySearchFilter(matchingIds)
    }

    this.onFilter?.(query, matchingIds)
  }
}
