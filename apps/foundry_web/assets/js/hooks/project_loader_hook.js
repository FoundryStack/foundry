export const ProjectLoaderHook = {
  mounted() {
    const canvasEl = document.getElementById("project-loader-canvas");
    const logEl = document.getElementById("project-loader-log");

    if (canvasEl) {
      canvasEl.width = window.innerWidth;
      canvasEl.height = window.innerHeight;
    }

    // Scroll log to bottom on init
    if (logEl) {
      logEl.scrollTop = logEl.scrollHeight;
      logEl.dataset.pinned = "true";
    }

    logEl?.addEventListener("scroll", () => {
      const pinned = logEl.scrollTop + logEl.clientHeight >= logEl.scrollHeight - 32;
      logEl.dataset.pinned = pinned ? "true" : "false";
    });

    this._startFireBackdrop(canvasEl);
  },

  async _startFireBackdrop(canvasEl) {
    if (!canvasEl) return;

    const logoEl = document.querySelector("#project-loader-stage img");
    let time = 0;
    let pointerPrimed = false;

    try {
      const cached = window._webglFluidSource;
      let source = cached;

      if (!source) {
        const response = await fetch("https://cdn.jsdelivr.net/npm/webgl-fluid@0.3.0/dist/webgl-fluid.umd.js");
        if (!response.ok) throw new Error(`fetch ${response.status}`);
        source = await response.text();
        source = source.replace("o.color=it()", "o.color=p.SPLAT_COLOR||it()");
        source = source.replace("N.forEach(s=>{s.color=it()})", "N.forEach(s=>{s.color=p.SPLAT_COLOR||it()})");
        source = source.replace(
          "const a=it();a.r*=10,a.g*=10,a.b*=10;",
          "const a=p.SPLAT_COLOR?{...p.SPLAT_COLOR}:it();if(!p.SPLAT_COLOR){a.r*=10,a.g*=10,a.b*=10;}"
        );
        window._webglFluidSource = source;
      }

      // Re-eval every time so WebGLFluid is re-initialized for this canvas
      delete window.WebGLFluid;
      window.eval(source);

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
      });

      this._fireTimer = window.setInterval(() => {
        if (!logoEl) return;

        const rect = logoEl.getBoundingClientRect();
        if (rect.width === 0) return;

        time += 0.13;

        const centerX = rect.left + rect.width / 2;
        const spread = rect.width * 0.08;
        const startX = centerX + Math.sin(time) * spread + Math.sin(time * 1.7) * (spread * 0.15);
        const startY = rect.top + rect.height * 0.8;
        const endY = startY - 7;

        if (!pointerPrimed) {
          canvasEl.dispatchEvent(
            new MouseEvent("mousedown", {
              clientX: startX,
              clientY: startY,
              bubbles: true
            })
          );
          pointerPrimed = true;
        }

        canvasEl.dispatchEvent(
          new MouseEvent("mousemove", {
            clientX: startX,
            clientY: startY,
            bubbles: true
          })
        );

        canvasEl.dispatchEvent(
          new MouseEvent("mousemove", {
            clientX: startX + (Math.random() - 0.5) * 0.6,
            clientY: endY,
            bubbles: true
          })
        );
      }, 60);
    } catch (_error) {
      // Silently fail if WebGL not supported
      if (canvasEl) canvasEl.remove();
    }
  },

  updated() {
    const logEl = document.getElementById("project-loader-log");
    if (logEl && logEl.dataset.pinned !== "false") {
      logEl.scrollTop = logEl.scrollHeight;
    }
  },

  destroyed() {
    if (this._fireTimer) {
      clearInterval(this._fireTimer);
      this._fireTimer = null;
    }
  }
};
