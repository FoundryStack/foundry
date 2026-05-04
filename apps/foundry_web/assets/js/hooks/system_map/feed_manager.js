import { UI_CONFIG } from '../../graph/config'
import { ResizablePanel } from './resizable_panel'

export class FeedManager {
  constructor() {
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
    })

    this._panel.sync({ force: true })
  }

  sync() {
    this._panel.sync()
  }

  destroy() {
    this._panel.destroy()
  }
}
