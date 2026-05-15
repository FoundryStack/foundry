# Solution: /project-manager 404 Bug Fixed

## Problem Summary

The `/project-manager` route returned 404 (or 500) in standalone Burrito mode while `/healthz` worked correctly. This prevented the Tauri desktop app from loading the project manager page.

## Root Cause

**SECRET_KEY_BASE was too short (56 bytes instead of required 64+ bytes).**

The hardcoded fallback secret in `config/runtime.exs` was:
```elixir
"foundry-standalone-secret-key-base-change-me-if-exposed"  # 56 bytes
```

Phoenix's Plug.Session.COOKIE middleware requires at least 64 bytes for cookie signing.

**Why only `/project-manager` failed:**
- `/healthz` returns JSON (no cookies set) ✓ Worked
- `/project-manager` renders HTML (sets CSRF/session cookies) ✗ Failed with 500

## Solution

### 1. Extended SECRET_KEY_BASE (Commit 4755db82)
Changed fallback to 66 bytes:
```elixir
"foundry-standalone-secret-key-base-change-me-if-exposed-0000000000"  # 66 bytes
```

### 2. Automated Validation (Commit 2d0bdc6a)
Added `verify_secret_key_base_config()` function to `scripts/release/build_burrito.sh`:
- Validates the fallback meets 64-byte minimum before building
- Provides clear error messages if misconfigured
- Called automatically during `mix release`

### 3. Validation in prepare_sidecar (Commit 840110f4)
Added config verification to `desktop/foundry-desktop/scripts/prepare_sidecar.sh`:
- Validates requirements before attempting build
- Catches configuration issues early with helpful messages

### 4. Documentation
Added comments in `config/runtime.exs` explaining the 64-byte requirement.

## Verification

All routes now work correctly:

```bash
# Test with proper SECRET_KEY_BASE (66+ bytes)
export FOUNDRY_STANDALONE=1
export FOUNDRY_HOME=/tmp/test
export SECRET_KEY_BASE="foundry-standalone-secret-key-base-change-me-if-exposed-0000000000"

# JSON endpoint (no cookies)
curl http://localhost:4000/healthz
# Returns: {"ok":true,"version":"0.1.0","mode":"standalone"}

# HTML endpoint (sets cookies)
curl http://localhost:4000/project-manager
# Returns: 200 with full HTML page
```

## Files Changed

1. `config/runtime.exs` - Extended fallback secret, added documentation
2. `scripts/release/build_burrito.sh` - Added validation function
3. `desktop/foundry-desktop/scripts/prepare_sidecar.sh` - Added pre-build validation
4. App-level code cleanup (4 files, commit f08923dd)

## Key Takeaway

Plug.Session.COOKIE is strict about SECRET_KEY_BASE length (64 bytes minimum). The cookie store validation happens during request rendering, not at startup, causing silent failures on HTML-rendering routes while JSON routes work fine. The automated validation prevents this issue from reoccurring.
