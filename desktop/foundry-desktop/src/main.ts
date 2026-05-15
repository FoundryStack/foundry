import { listen } from "@tauri-apps/api/event";

type LaunchPayload = {
  message: string;
};

window.addEventListener("DOMContentLoaded", async () => {
  const note = document.querySelector<HTMLElement>("#shell-note");
  const runtime = document.querySelector<HTMLElement>("#runtime-status");
  const windowStatus = document.querySelector<HTMLElement>("#window-status");
  const health = document.querySelector<HTMLElement>("#health-status");

  const applyMessage = (message: string, failed = false) => {
    if (note) {
      note.textContent = message;
      note.dataset.state = failed ? "error" : "loading";
    }

    if (runtime) {
      runtime.textContent = failed ? "Launch failed" : "Sidecar starting";
    }

    if (windowStatus) {
      windowStatus.textContent = failed ? "Stayed on shell" : "Handing off";
    }

    if (health) {
      health.textContent = failed ? "Startup error" : "Waiting for /healthz";
    }
  };

  applyMessage("Preparing Foundry sidecar...");

  await listen<LaunchPayload>("foundry://launch-status", (event) => {
    applyMessage(event.payload.message);
  });

  await listen<LaunchPayload>("foundry://launch-error", (event) => {
    applyMessage(event.payload.message, true);
  });
});
