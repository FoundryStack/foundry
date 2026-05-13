# Packaging

This directory holds release automation assets that are safe to version inside the
application repository:

- `github/*.example` contains workflow proposals for the platform team to apply manually
- `homebrew/foundry.rb.eex` renders the tap formula from release asset URLs and checksums
- `scripts/release/*` performs the build and packaging work that GitHub Releases will call

Per ADR-006, actual `.github/workflows/*` application remains an infrastructure step.
