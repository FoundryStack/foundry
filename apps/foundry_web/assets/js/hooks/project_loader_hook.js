export const ProjectLoaderHook = {
  mounted() {
    this._fadeOutNotified = false;
    this._fadeOutTimer = null;
    this._lastLoading = this.el.dataset.loading;

    const logEl = this.el.querySelector("#project-loader-log");

    if (logEl) {
      logEl.scrollTop = logEl.scrollHeight;
      logEl.dataset.pinned = "true";

      logEl.addEventListener("scroll", () => {
        const pinned = logEl.scrollTop + logEl.clientHeight >= logEl.scrollHeight - 32;
        logEl.dataset.pinned = pinned ? "true" : "false";
      });
    }
  },

  updated() {
    const logEl = this.el.querySelector("#project-loader-log");
    const loading = this.el.dataset.loading;

    if (this._lastLoading !== "false" && loading === "false") {
      this._notifyFadeOutAfterTransition();
    }

    this._lastLoading = loading;

    if (logEl && logEl.dataset.pinned !== "false") {
      logEl.scrollTop = logEl.scrollHeight;
    }
  },

  _notifyFadeOutAfterTransition() {
    if (this._fadeOutNotified) return;

    const finish = () => {
      if (this._fadeOutNotified) return;
      this._fadeOutNotified = true;

      if (this._fadeOutTimer) {
        clearTimeout(this._fadeOutTimer);
        this._fadeOutTimer = null;
      }

      // Hide the full overlay immediately on the client in case the LiveView
      // removal patch arrives slightly later than the opacity transition.
      this.el.style.display = "none";
      this.el.style.visibility = "hidden";

      this.pushEvent("project_loader_faded_out", {});
    };

    this.el.addEventListener(
      "transitionend",
      (event) => {
        if (event.target === this.el && event.propertyName === "opacity") {
          finish();
        }
      },
      { once: true }
    );

    this._fadeOutTimer = window.setTimeout(finish, 700);
  },

  destroyed() {
    if (this._fadeOutTimer) {
      clearTimeout(this._fadeOutTimer);
      this._fadeOutTimer = null;
    }
  }
};
