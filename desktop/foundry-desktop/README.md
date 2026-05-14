# Foundry Desktop

Thin Tauri shell scaffold for the phased Foundry desktop distribution plan.

## Local development

```bash
npm install
npm run tauri:dev
```

## Notes

- The shell is intentionally thin and should treat Foundry as a sidecar/runtime, not a second backend
- `npm run prepare:sidecar:dev` may use a local `mix foundry.studio` wrapper for contributor workflows
- `npm run prepare:sidecar` and packaged `.app` builds must embed a real Burrito-produced standalone sidecar
