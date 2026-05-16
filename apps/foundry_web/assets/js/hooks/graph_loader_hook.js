let _instance = null
let _dismissRequested = false

export const requestGraphLoaderDismiss = () => {
  if (_instance) {
    _instance.dismiss()
  } else {
    _dismissRequested = true
  }
}

export const GraphLoaderHook = {
  mounted() {
    _instance = this
    this._dismissTimer = null
    this._fireTimer = null
    this._dismissed = false
    this._pendingDismiss = false
    this._readyToDismiss = false
    this._mountedAt = Date.now()

    const canvasEl = document.getElementById("graph-loader-canvas")
    if (canvasEl) {
      canvasEl.width = window.innerWidth
      canvasEl.height = window.innerHeight
    }
    const logEl = document.getElementById("graph-loader-log")

    // Populate log from server-rendered content (already in the <pre> from @graph_loader_logs)
    if (logEl) {
      logEl.scrollTop = logEl.scrollHeight
      logEl.dataset.pinned = "true"

      logEl.addEventListener("scroll", () => {
        const pinned = logEl.scrollTop + logEl.clientHeight >= logEl.scrollHeight - 32
        logEl.dataset.pinned = pinned ? "true" : "false"
      })
    }

    this._startFireBackdrop(canvasEl)
  },

  async _startFireBackdrop(canvasEl) {
    if (!canvasEl) return

    const logoEl = document.querySelector("#graph-loader-stage img")
    let time = 0
    let pointerPrimed = false

    try {
      // If dismissed before library loaded, skip initialization
      if (this._dismissed) return

      if (!window.WebGLFluid) {
        throw new Error("WebGLFluid library not loaded")
      }

      if (this._dismissed) return

      window.WebGLFluid(canvasEl, {
        TRIGGER: "hover",
        IMMEDIATE: false,
        AUTO: false,
        SIM_RESOLUTION: 128,
        DYE_RESOLUTION: 1024,
        DENSITY_DISSIPATION: 0.97,
        VELOCITY_DISSIPATION: 0.96,
        PRESSURE: 0.8,
        CURL: 10,
        SPLAT_RADIUS: 0.04,
        SPLAT_FORCE: 820,
        SHADING: true,
        SPLAT_COLOR: { r: 1.65, g: 0.34, b: 0.03 },
        COLORFUL: false,
        TRANSPARENT: true,
        BLOOM: true,
        BLOOM_ITERATIONS: 8,
        BLOOM_RESOLUTION: 256,
        BLOOM_INTENSITY: 0.18,
        BLOOM_THRESHOLD: 0.7,
        SUNRAYS: false
      })

      // Fade canvas in immediately after WebGL initialization
      if (!this._dismissed) canvasEl.style.opacity = "1"

      // Mark ready now so dismiss() will execute as soon as layout completes.
      this._readyToDismiss = true

      this._fireTimer = window.setInterval(() => {
        if (this._dismissed) {
          clearInterval(this._fireTimer)
          this._fireTimer = null
          return
        }
        if (!logoEl) return
        const rect = logoEl.getBoundingClientRect()
        if (rect.width === 0) return

        time += 0.13
        const centerX = rect.left + rect.width / 2
        const spread = rect.width * 0.08
        const startX = centerX + Math.sin(time) * spread + Math.sin(time * 1.7) * (spread * 0.15)
        const startY = rect.top + rect.height * 0.8
        const endY = startY - 7

        if (!pointerPrimed) {
          canvasEl.dispatchEvent(new MouseEvent("mousedown", { clientX: startX, clientY: startY, bubbles: true }))
          pointerPrimed = true
        }
        canvasEl.dispatchEvent(new MouseEvent("mousemove", { clientX: startX, clientY: startY, bubbles: true }))
        canvasEl.dispatchEvent(new MouseEvent("mousemove", { clientX: startX + (Math.random() - 0.5) * 0.6, clientY: endY, bubbles: true }))
      }, 60)

      if (_dismissRequested) {
        _dismissRequested = false
        this._executeDismiss()
      } else if (this._pendingDismiss) {
        this._executeDismiss()
      }
    } catch (_err) {
      // WebGL not supported or fetch failed — skip effect, still show loader
      if (canvasEl) canvasEl.remove()
      this._readyToDismiss = true
      if (_dismissRequested) {
        _dismissRequested = false
        this._executeDismiss()
      } else if (this._pendingDismiss) {
        this._executeDismiss()
      }
    }
  },

  dismiss() {
    if (this._dismissed) return

    if (!this._readyToDismiss) {
      // Fire not started yet — queue the dismiss for after fire starts
      this._pendingDismiss = true
      return
    }

    this._executeDismiss()
  },

  _executeDismiss() {
    if (this._dismissed) return
    this._dismissed = true

    if (this._fireTimer) {
      clearInterval(this._fireTimer)
      this._fireTimer = null
    }

    const wrapper = document.getElementById("graph-loader-wrapper")
    if (!wrapper) return

    wrapper.style.transition = "opacity 600ms ease-out"
    wrapper.style.opacity = "0"

    this._dismissTimer = setTimeout(() => {
      if (wrapper && wrapper.parentElement) wrapper.remove()
      if (_instance === this) _instance = null
      this._dismissTimer = null
    }, 20)
  },

  destroyed() {
    this._dismissed = true
    if (this._dismissTimer) {
      clearTimeout(this._dismissTimer)
      this._dismissTimer = null
    }
    if (this._fireTimer) {
      clearInterval(this._fireTimer)
      this._fireTimer = null
    }
    if (_instance === this) _instance = null
  }
}
