export const NODE_TYPE_CONFIG = {
  resource:  { colorToken: 'bl', canExpand: true,  childrenKind: 'actions' },
  reactor:   { colorToken: 'pu', canExpand: true,  childrenKind: 'steps'   },
  transfer:  { colorToken: 'gn', canExpand: true,  childrenKind: 'steps'   },
  job:       { colorToken: 'pu', canExpand: false, childrenKind: null      },
  trigger:   { colorToken: 'ac', canExpand: false, childrenKind: null      },
  rule:      { colorToken: 'yw', canExpand: false, childrenKind: null      },
  blueprint: { colorToken: 'ac', canExpand: false, childrenKind: null      },
  external:  { colorToken: 't3', canExpand: false, childrenKind: null      },
}

export const HTML_LABEL_CONFIG = [
  { query: 'node[nodeKind="entity"]',  halign: 'center', valign: 'center', halignBox: 'center', valignBox: 'center', tpl: null },
  { query: 'node.domain-cluster',      halign: 'left',   valign: 'top',    halignBox: 'left',   valignBox: 'top',    tpl: null },
  { query: 'node[nodeKind="cluster"]', halign: 'left', valign: 'top', halignBox: 'left', valignBox: 'top', tpl: null },
  { query: 'node[nodeKind="step"]',    halign: 'center', valign: 'center', halignBox: 'center', valignBox: 'center', tpl: null },
  { query: 'node[nodeKind="action"]',  halign: 'center', valign: 'center', halignBox: 'center', valignBox: 'center', tpl: null },
]

export const UI_CONFIG = {
  nodeThreshold: 200,
  searchDebounce: 150,
  sidebarWidth: { default: 240, min: 180, max: 600 },
  drawerWidth: { default: 380 },
  storageKeys: {
    sidebarWidth: 'foundry:sidebar-width',
    drawerWidth: 'foundry:drawer-width',
  },
}
