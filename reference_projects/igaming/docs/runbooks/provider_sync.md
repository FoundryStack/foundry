# Provider Sync Runbook

## Overview

Synchronizes the game catalog from a provider's API and creates or updates local records. Fully idempotent.

## Steps

1. **Load Provider** — Fetches and validates the provider configuration, ensures status is :active
2. **Fetch Games** — Calls the provider's API to retrieve the current list of games with metadata
3. **Sync Games** — Creates or updates Game records for each fetched game
4. **Update Catalog** — Updates GameCatalog entries to mark games as visible/available

## Idempotency

The sync is idempotent via the `provider_id` key. Running the sync multiple times is safe — duplicate game creates are handled by idempotent merge semantics, and GameCatalog updates are atomic.

## Compliance

- **RG-MGA-006** — Provider Agreements — ensures only approved providers are synced
- **RG-UK-007** — Game Certification — ensures only certified games are added to the catalog
