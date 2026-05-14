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
- `npm run prepare:sidecar` now reuses an existing verified sidecar instead of rebuilding it on every run; set `FOUNDRY_DESKTOP_FORCE_REBUILD=1` to force a fresh Burrito build
- Packaged sidecar launches provision `FOUNDRY_STANDALONE=1` and a persisted `SECRET_KEY_BASE` at runtime; the secret is not baked into the Burrito build artifact
- Direct release starts such as `_build/prod/rel/foundry/bin/foundry start` still require the normal production environment variables
