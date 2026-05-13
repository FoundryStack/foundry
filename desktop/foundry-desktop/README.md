# Foundry Desktop

Thin Tauri shell scaffold for the phased Foundry desktop distribution plan.

## Current scope

- Phase 1 shipping path is still the standalone Burrito runtime
- This app is the phase 2 wrapper shell
- GitHub workflow application remains a platform-owned infrastructure step

## Local development

```bash
npm install
npm run tauri:dev
```

## Notes

- The shell is intentionally thin and should treat Foundry as a sidecar/runtime, not a second backend
- macOS PATH bootstrapping is planned here because GUI apps do not inherit shell PATH reliably
