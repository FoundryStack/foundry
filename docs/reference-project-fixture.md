# docs/reference-project-fixture.md — iGaming Reference Project

> **Purpose:** This document declares the structure of the iGaming reference project
> used to validate every phase's acceptance criteria in BUILD_SEQUENCE.md.
> It is the written contract that the actual code in `reference_projects/igaming/`
> must implement. Write the code from this document, not the other way around.
>
> **Status:** Canonical. Changes to this document require review — every phase's
> "done when" criteria depends on what is declared here.
>
> **Closes:** Gap #54 in REVIEW_AND_PLAN.md.
>
> **ADR alignment:** This fixture reflects decisions from ADR-001 through ADR-010.
> See the ADR Alignment section at the bottom for a cross-reference.
>
> **Amendment 2026-04:** Promotions no longer use a standalone Blueprint module pattern.
> Bonus orchestration is modeled with Ash resources (`BonusTrigger`,
> `BonusConditionGroup`, `BonusCondition`, `BonusExecution`, `BonusEvent`) plus
> `BonusEvaluationReactor`. Graph relationships are inferred from executable source
> first; metadata/prose fallbacks are legacy-only.

---

## Project Identity

```elixir
# .foundry/manifest.exs (reference project)
project_name: "IgamingRef",
domain_type: :igaming,
```

Root application module: `IgamingRef`
OTP application name: `:igaming_ref`

---

## Domains

The reference project has five domains. The `Finance` and `Players` domains exercise the
double-entry ledger, multi-currency accounts, KYC, and self-exclusion patterns.
The `Promotions` domain exercises a resource-driven bonus engine pattern. The `Ops` domain holds the
PIIVault and AuditEntry resources required for GDPR-safe audit logging. The `Gaming`
domain exercises provider adapter versioning (ADR-007), back-office catalog CRUD, async
catalog sync via Oban, and read-only catalog aggregation for player-facing presentation.

| Domain module | Purpose |
|---|---|
| `IgamingRef.Finance` | AshDoubleEntry ledger, wallets, transfers — the financial core |
| `IgamingRef.Players` | Player accounts, KYC documents (presigned S3), self-exclusion |
| `IgamingRef.Promotions` | Bonus campaigns, grants, triggers, conditions, executions, events |
| `IgamingRef.Ops` | AuditEntry, PIIVault — GDPR-safe append-only audit log |
| `IgamingRef.Gaming` | Provider adapter versioning, game catalog CRUD, sync jobs, catalog aggregation |

---

## Resources

### `IgamingRef.Finance` domain

#### `IgamingRef.Finance.Wallet`

**ADR basis:** ADR-003 (multi-currency account structure), ADR-008 (AshDoubleEntry adoption).

One `Wallet` row represents one currency-bucket account for one player. A GBP player has
four Wallet rows: `real_gbp`, `bonus_gbp`, `free_spin_winnings_gbp`, `locked_gbp`.
`Wallet` extends `AshDoubleEntry.Account` — it is not a standalone Ash resource.

- **Type:** Ash resource (`ash_postgres`) extending `AshDoubleEntry.Account`
- **Sensitive:** yes
- **Description:** One AshDoubleEntry account per currency per wallet bucket per player.
  Balance is always derived as `SUM(credits) - SUM(debits)` over immutable LedgerEntry rows.
  Never stores a mutable balance field. See ADR-001, ADR-003.
- **Attributes:** `id`, `player_id` (belongs_to Players.Player), `currency` (string,
  ISO 4217 code), `bucket` (atom: `:real | :bonus | :free_spin_winnings | :locked`),
  `status` (atom: `:active | :frozen | :closed`), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `freeze`, `close`
  — no `credit`/`debit` directly; all balance mutations go through `IgamingRef.Finance.Transfer`
    (AshDoubleEntry.Transfer). Direct credit/debit is forbidden by policy (INV-001).
- **State machine:** yes — states: `:active`, `:frozen`, `:closed`;
  transitions: `freeze` (active→frozen), `unfreeze` (frozen→active), `close` (active|frozen→closed)
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012) — soft delete only
- **Compliance links:** `RG-MGA-001` (wallet integrity), `RG-UK-003` (balance accuracy)
- **Rate limited:** no (mutations go through Transfer, not direct debit action)
- **Telemetry prefix:** `[:igaming_ref, :finance, :wallet]`

#### `IgamingRef.Finance.LedgerEntry`

**ADR basis:** ADR-001 (double-entry ledger), ADR-008 (AshDoubleEntry adoption).

`LedgerEntry` extends `AshDoubleEntry.Balance` — the library's immutable movement record.
The no-update/no-destroy constraint is enforced at the library level, not only by policy.

- **Type:** Ash resource (`ash_postgres`) extending `AshDoubleEntry.Balance`
- **Sensitive:** yes
- **Description:** Immutable record of every financial movement. Append-only — no `update`
  or `destroy` actions exist or are permitted. Balance is always derived from the sum of
  LedgerEntry rows; the Wallet resource carries no mutable balance field. See ADR-001.
- **Attributes:** `id`, `wallet_id` (belongs_to Wallet), `amount` (`Ash.Type.Money`),
  `direction` (atom: `:credit | :debit`), `kind`
  (atom: `:deposit | :withdrawal | :bonus | :wager | :win | :reversal`),
  `idempotency_key` (string, unique), `reference_id` (string), `inserted_at`
- **Actions:** `read`, `create` — no `update`, no `destroy` (enforced by AshDoubleEntry)
- **State machine:** no
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-MGA-001`, `RG-MGA-002` (ledger immutability), `RG-UK-003`
- **Telemetry prefix:** `[:igaming_ref, :finance, :ledger_entry]`

#### `IgamingRef.Finance.Transfer`

**ADR basis:** ADR-008 (AshDoubleEntry adoption). All balance mutations go through this resource.

- **Type:** Ash resource (`ash_postgres`) extending `AshDoubleEntry.Transfer`
- **Sensitive:** yes
- **Description:** The single mechanism for all balance mutations. Wraps AshDoubleEntry.Transfer
  so domain code never calls AshDoubleEntry directly. Every debit/credit pair is one Transfer.
- **Attributes:** `id`, `from_wallet_id` (belongs_to Wallet, nullable for deposits),
  `to_wallet_id` (belongs_to Wallet, nullable for withdrawals), `amount` (`Ash.Type.Money`),
  `kind` (atom: `:deposit | :withdrawal | :bonus_grant | :wager | :win`),
  `idempotency_key` (string, unique), `inserted_at`
- **Actions:** `read`, `create` — no `update`, no `destroy`
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-MGA-001`, `RG-MGA-002`
- **Telemetry prefix:** `[:igaming_ref, :finance, :transfer]`

#### `IgamingRef.Finance.WithdrawalRequest`

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** A player's request to withdraw funds. Goes through approval and provider
  routing. Balance debit happens in `WithdrawalTransfer` only after this reaches `:approved`.
- **Attributes:** `id`, `player_id`, `wallet_id`, `amount` (`Ash.Type.Money`),
  `status` (atom: `:pending | :approved | :processing | :completed | :rejected | :cancelled`),
  `provider` (string), `provider_reference` (string, nullable), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `approve`, `reject`, `cancel`, `mark_processing`, `mark_completed`
- **State machine:** yes — states mirror status attribute
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-014` (withdrawal processing), `RG-MGA-007` (withdrawal limits)
- **Telemetry prefix:** `[:igaming_ref, :finance, :withdrawal_request]`

---

### `IgamingRef.Players` domain

#### `IgamingRef.Players.Player`

**ADR basis:** ADR-004 (wallet draw order as player preference), ADR-006 (PIIVault pattern).

`wallet_draw_order` is a first-class player preference field, not a platform constant.
`jurisdiction` drives compliance rule overrides (e.g. Germany forces draw order regardless
of player preference). Both fields are required for UKGC and MGA compliance. PII fields
are extracted to `IgamingRef.Ops.PIIVault` on every audit entry write — see ADR-006.

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes (PII-bearing — email, date_of_birth extracted to PIIVault on audit)
- **Description:** A registered player account. Root of all player-scoped data. Carries
  wallet draw order preference (UKGC requirement) and jurisdiction for compliance overrides.
- **Attributes:**
  - `id`, `email` (string, unique), `username` (string, unique)
  - `date_of_birth` (date) — PII, extracted to PIIVault on audit writes
  - `country_code` (string)
  - `jurisdiction` (atom: `:uk | :mga | :de | :unknown`) — drives compliance rule overrides;
    `:de` players always use `[:real, :bonus]` draw order regardless of preference
  - `kyc_status` (atom: `:unverified | :pending | :verified | :rejected`)
  - `risk_level` (atom: `:low | :medium | :high`)
  - `wallet_draw_order` ({:array, :atom}) — player preference for bucket draw sequence;
    default `[:bonus, :real, :free_spin_winnings]`; UK players may change via account settings;
    `:de` jurisdiction overrides this field silently at bet placement time
  - `status` (atom: `:active | :suspended | :self_excluded | :closed`)
  - `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `update_kyc_status`, `update_draw_order`, `suspend`,
  `reinstate`, `self_exclude`, `close`
  - `update_draw_order` is an audited action; staff override requires a reason
- **State machine:** yes — status states;
  transitions: `suspend` (active→suspended), `reinstate` (suspended→active),
  `self_exclude` (active→self_excluded), `close` (active|suspended→closed)
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-002` (player verification), `RG-MGA-003` (KYC requirements),
  `RG-UK-008` (self-exclusion), `RG-UK-004` (player-controlled draw order)
- **Rate limited:** no
- **Telemetry prefix:** `[:igaming_ref, :players, :player]`

#### `IgamingRef.Players.KYCDocument`

**ADR basis:** ADR-009 (presigned S3 KYC upload).

KYC files (passport scans, utility bills, bank statements) never transit the Phoenix
application server. The Phoenix backend generates a presigned URL; the browser uploads
directly to S3; a virus-scan webhook drives the state machine.

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Tracks a single KYC document upload. The file content never reaches
  the application — only metadata, presigned URL tokens, and scan results are stored.
  State machine reflects document lifecycle: requested → uploaded → scanning → pending_review
  (clean) or quarantined (infected). See ADR-009.
- **Attributes:** `id`, `player_id`, `document_type`
  (atom: `:passport | :drivers_licence | :utility_bill | :bank_statement`),
  `original_filename` (string), `mime_type` (string), `file_size_bytes` (integer),
  `s3_key` (string, nullable — set after successful upload),
  `scan_result` (atom: `:clean | :infected | nil`),
  `status` (atom: `:requested | :uploaded | :scanning | :pending_review | :approved | :quarantined | :rejected`),
  `inserted_at`, `updated_at`
- **Actions:** `read`, `request_upload` (generates presigned URL token),
  `mark_uploaded` (called by S3 completion webhook), `mark_scan_result`
  (called by virus scan webhook — transitions to `:pending_review` or `:quarantined`),
  `approve`, `reject`
- **State machine:** yes — states mirror status attribute;
  transitions: `mark_uploaded` (:requested→:uploaded), virus scan result
  (:uploaded→:scanning→:pending_review | :quarantined)
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-MGA-003`, `RG-UK-002`
- **Telemetry prefix:** `[:igaming_ref, :players, :kyc_document]`

**Supporting resource:** `IgamingRef.Players.KYCUploadToken` — presigned URL token, short TTL
(15 min), single-use. Not sensitive (no file content). No paper trail required.

#### `IgamingRef.Players.SelfExclusionRecord`

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Immutable record of a self-exclusion event. Append-only.
- **Attributes:** `id`, `player_id`, `excluded_at`,
  `exclusion_type` (atom: `:temporary | :permanent`),
  `duration_days` (integer, nullable), `reinstated_at` (nullable), `inserted_at`
- **Actions:** `read`, `create`, `mark_reinstated` — no `destroy`
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-008`, `RG-MGA-009` (self-exclusion integrity)
- **Telemetry prefix:** `[:igaming_ref, :players, :self_exclusion_record]`

---

### `IgamingRef.Promotions` domain

**ADR basis:** ADR-002 (configurable runtime logic), ADR-005 (bonus rule transparency).

Promotions uses Ash resources (not standalone Blueprint modules) for manager-configured
bonus logic. Runtime behavior is composed from:

- `BonusTrigger` (`:deposit_completed`, `:manual_grant`)
- `BonusConditionGroup` (`:all` / `:any`)
- `BonusCondition` (`:campaign_active`, `:campaign_not_expired`,
  `:player_not_self_excluded`, `:player_country_in`, `:min_deposit_amount`,
  `:no_active_bonus`)
- `BonusExecution` (`:grant_deposit_match`, `:grant_fixed_amount`,
  `:set_wagering_requirement`)
- `BonusEvent` (inbound runtime event, idempotent, auditable)

`BonusEvaluationReactor` evaluates `BonusEvent` against these resources and invokes
`BonusGrantTransfer` for money-moving execution paths.

#### `IgamingRef.Promotions.BonusCampaign`

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** no
- **Description:** A configured bonus campaign with lifecycle and base reward settings.
  Dynamic trigger/condition/execution logic is defined by related configuration resources.
- **Attributes:** `id`, `name` (string),
  `kind` (atom: `:deposit_match | :free_spins | :cashback`),
  `status` (atom: `:draft | :active | :paused | :expired`),
  `bonus_amount` (`Ash.Type.Money`), `wagering_multiplier` (decimal),
  `max_redemptions` (integer, nullable), `starts_at` (datetime), `expires_at` (datetime),
  `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `update`, `activate`, `pause`, `expire`
- **State machine:** yes — status states
- **Paper trail:** no (not sensitive)
- **Archival:** no
- **Compliance links:** `RG-MGA-005` (bonus terms transparency), `RG-UK-011`
  (bonus wagering disclosure)
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_campaign]`

#### `IgamingRef.Promotions.BonusGrant`

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** no
- **Description:** A specific bonus awarded to a player from a campaign.
  Tracks wagering progress and lifecycle transitions.
- **Attributes:** `id`, `player_id`, `campaign_id`,
  `amount` (`Ash.Type.Money`), `wagering_remaining` (decimal),
  `status` (atom: `:active | :wagered | :forfeited | :expired`),
  `granted_at`, `expires_at`, `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `apply_wager`, `forfeit`, `expire`, `complete`
  - `forfeit` always requires an audit reason matching a declared forfeiture trigger
- **State machine:** yes — status states
- **Paper trail:** no
- **Archival:** no
- **Compliance links:** `RG-MGA-005`, `RG-UK-011`
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_grant]`

---

### `IgamingRef.Gaming` domain

**ADR basis:** ADR-007 (provider API versioning via Strangler Fig).

The Gaming domain has three responsibilities: managing provider integration credentials and
adapter version dispatch; giving back-office operators CRUD control over the game catalog;
and aggregating published games into a unified read-only view for player-facing surfaces.
Provider adapter modules are versioned in place — a new API version from a provider gets
a new module, not a modified one. Traffic is routed to the correct adapter version by
`ProviderConfig.active_adapter_version`. The `adapter_verify_failed` notification declared
in the manifest is owned and triggered by this domain.

#### `IgamingRef.Gaming.Adapters.PragmaticPlayV1`

**ADR basis:** ADR-007 (Strangler Fig). First concrete adapter in the reference project.
Exercises the `adapter` node type and establishes the `ProviderAdapter` behaviour contract.
A V2 stub is included to demonstrate the side-by-side versioning pattern — it is registered
but not set as active, so contract tests must pass before it can be promoted.

- **Type:** Adapter module — `adapter` node type
- **Sensitive:** no (logic only — credentials live in `ProviderConfig`)
- **Description:** Pragmatic Play game catalog adapter, API version 1. Implements
  `IgamingRef.Gaming.ProviderAdapter` behaviour. Fetches game list, normalises response
  to `GameEntry` structs. Declared via `@api_version "v1"` and `@supported_versions ["v1"]`.
- **Behaviour callbacks:** `fetch_catalog/1`, `verify_connection/1`, `normalize_game/1`
- **Telemetry prefix:** `[:igaming_ref, :gaming, :pragmatic_play_v1]`
- **ADRs:** `ADR-007`

#### `IgamingRef.Gaming.Adapters.PragmaticPlayV2`

- **Type:** Adapter module — `adapter` node type
- **Sensitive:** no
- **Description:** Pragmatic Play game catalog adapter, API version 2. Side-by-side with V1
  per the Strangler Fig pattern. Not yet set as active on any `ProviderConfig` row. Must pass
  contract tests before promotion. Declared via `@api_version "v2"` and
  `@supported_versions ["v1", "v2"]` (backward-compatible).
- **Behaviour callbacks:** `fetch_catalog/1`, `verify_connection/1`, `normalize_game/1`
- **Telemetry prefix:** `[:igaming_ref, :gaming, :pragmatic_play_v2]`
- **ADRs:** `ADR-007`

#### `IgamingRef.Gaming.ProviderConfig`

Stores per-provider credentials, endpoint configuration, and the currently active adapter
version. Sensitive because it holds API keys. `active_adapter_version` is the routing field
that `ProviderSyncReactor` reads to select which versioned adapter module to invoke.
Changing `active_adapter_version` is a `:behavioral` change — it alters runtime dispatch
and requires domain lead approval before apply.

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes (holds API credentials)
- **Description:** Per-provider integration config. Carries API credentials (encrypted at rest),
  the base endpoint URL, the currently active adapter version string, and enabled/disabled
  state. The `active_adapter_version` field controls adapter module dispatch in
  `ProviderSyncReactor`. Changing it is a `:behavioral` class change. See ADR-007.
- **Attributes:** `id`, `provider_slug` (atom: `:pragmatic_play` — extendable),
  `api_key` (string, encrypted), `base_url` (string),
  `active_adapter_version` (string, e.g. `"v1"` or `"v2"`),
  `status` (atom: `:active | :disabled | :suspended`),
  `last_verified_at` (datetime, nullable), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `update`, `disable`, `suspend`, `verify_connection`
  - `verify_connection` calls the adapter's `verify_connection/1` and updates
    `last_verified_at`; failure triggers the `adapter_verify_failed` notification
- **State machine:** yes — status states;
  transitions: `disable` (active→disabled), `suspend` (active→suspended),
  `reactivate` (disabled|suspended→active)
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-MGA-011` (operator must be able to suspend a provider immediately)
- **Telemetry prefix:** `[:igaming_ref, :gaming, :provider_config]`

#### `IgamingRef.Gaming.Game`

The canonical game record for the back-office catalog. One row per game per provider.
`external_id` is the provider's own identifier. `certification_status` gates the `publish`
action — a game cannot be made visible to players until its RTP is provider-certified
(RG-MGA-006). Category accuracy is required for self-exclusion tooling (RG-UK-015).

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** no
- **Description:** A game sourced from a provider. Represents the back-office catalog entry.
  `certification_status` must be `:certified` before `publish` is permitted. Category must
  be accurate for self-exclusion filters to work correctly. Created and updated by
  `ProviderSyncReactor`; managed by back-office operators via `publish`/`unpublish`/`suspend`.
- **Attributes:** `id`, `provider_config_id` (belongs_to ProviderConfig),
  `external_id` (string — provider's own game ID, unique per provider),
  `title` (string), `studio` (string — game studio/developer name),
  `category` (atom: `:slot | :live_casino | :table | :virtual_sports | :crash`),
  `rtp` (decimal — return-to-player percentage, 2dp),
  `volatility` (atom: `:low | :medium | :high | :unknown`),
  `certification_status` (atom: `:uncertified | :pending_certification | :certified | :certification_expired`),
  `status` (atom: `:draft | :published | :unpublished | :suspended`),
  `provider_metadata` (map — raw provider fields, unvalidated),
  `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `update`, `publish`, `unpublish`, `suspend`, `reinstate`
  - `publish` is guarded by `GameRTPCertified` rule — blocked if `certification_status`
    is not `:certified`
  - `suspend` must be immediately executable — no approval gate (RG-MGA-011)
- **State machine:** yes — status states;
  transitions: `publish` (draft|unpublished→published), `unpublish` (published→unpublished),
  `suspend` (published→suspended), `reinstate` (suspended→published)
- **Paper trail:** no (not sensitive — game metadata is not PII or financial)
- **Archival:** no
- **Compliance links:** `RG-MGA-006` (RTP accuracy gate before publish), `RG-UK-015`
  (category accuracy for self-exclusion tooling), `RG-MGA-011` (immediate suspend capability)
- **Telemetry prefix:** `[:igaming_ref, :gaming, :game]`

#### `IgamingRef.Gaming.GameVersion`

Append-only record of every content change pushed by a provider for a game — title
corrections, RTP updates, asset refreshes, certification state changes. Gives operators
and compliance auditors a complete history of what changed and when. Required for RTP
accuracy compliance: if a provider updates an RTP mid-operation, the change is visible
in this log with a timestamp.

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** no
- **Description:** Immutable changelog entry for a `Game` record. Created by
  `ProviderSyncReactor` whenever provider-sourced fields differ from stored values.
  No `update` or `destroy` actions — the history is tamper-evident by construction.
- **Attributes:** `id`, `game_id` (belongs_to Game),
  `changed_fields` (map — `{field_name: {old_value, new_value}}`),
  `sync_source` (atom: `:scheduled_sync | :manual_refresh`),
  `provider_reported_at` (datetime, nullable — timestamp from provider payload if present),
  `inserted_at`
- **Actions:** `read`, `create` — no `update`, no `destroy`
- **Paper trail:** no (is itself the changelog primitive)
- **Archival:** no
- **Compliance links:** `RG-MGA-006`
- **Telemetry prefix:** `[:igaming_ref, :gaming, :game_version]`

#### `IgamingRef.Gaming.GameCatalog`

Read-only aggregated view. Not a stored table — backed by a custom Ash read action over
`Game` with a `status: :published` filter and a join to `ProviderConfig` to enforce the
`status: :active` provider gate. Exercises the read-only derived resource pattern:
`data_layer: :custom` (no `ash_postgres` table, no write actions). Player-facing API
and LiveView surfaces consume this resource rather than `Game` directly, so the
published/unpublished and active-provider distinctions are enforced at the resource boundary.

- **Type:** Ash resource (read-only, `data_layer: :custom`)
- **Sensitive:** no
- **Description:** Player-facing aggregated game catalog. Read-only view of all `:published`
  games from `:active` providers, ordered by category then title. No stored table — queries
  delegate to `Game` joined to `ProviderConfig`. No write actions exist or are possible.
  Exercises the custom-data-layer read-only resource pattern.
- **Attributes:** Mirrors `Game` minus `provider_metadata`, `certification_status`,
  and back-office operational fields. Exposes: `id`, `title`, `studio`, `category`, `rtp`,
  `volatility`, `provider_slug`, `status` (always `:published` from this resource's perspective)
- **Actions:** `read`, `list_by_category`, `search`
  - `list_by_category` — filters by `category` atom
  - `search` — full-text search over `title` and `studio`
- **Compliance links:** `RG-UK-015` (category exposure for self-exclusion tooling)
- **Telemetry prefix:** `[:igaming_ref, :gaming, :game_catalog]`

---

### `IgamingRef.Ops` domain

**ADR basis:** ADR-006 (PIIVault pattern for GDPR vs audit log conflict).

The `Ops` domain exists specifically to implement the PIIVault pattern. It is the minimum
required to make the reference project's audit log GDPR-compliant. The `AuditEntry` is
append-only. On GDPR erasure, only `PIIVault` rows are deleted — `AuditEntry` rows are
retained with hashes in place of personal values. The hash chain remains intact.

#### `IgamingRef.Ops.AuditEntry`

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Append-only audit log entry. PII field values in `before_state` and
  `after_state` are replaced with SHA-256 hashes at write time; original values are stored
  in `PIIVault`. The `entry_hash` is computed over content including the PII hashes. See ADR-006.
- **Attributes:** `id`, `resource_module` (string), `resource_id` (string),
  `action` (string), `actor_id` (string, nullable),
  `before_state` (map — PII values replaced with hashes), `after_state` (map — same),
  `entry_hash` (string — SHA-256 of full entry including PII hashes),
  `inserted_at`
- **Actions:** `read`, `create` — no `update`, no `destroy`
- **Paper trail:** no (is itself the audit primitive)
- **Archival:** no (retention governed by regulatory minimum; never soft-deleted)
- **Compliance links:** `RG-MGA-010` (audit retention), `RG-UK-GDPR-001` (erasure compatibility)
- **Telemetry prefix:** `[:igaming_ref, :ops, :audit_entry]`

#### `IgamingRef.Ops.PIIVault`

- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Stores original PII field values keyed by `(audit_entry_id, field_name)`.
  Deleted on GDPR erasure request. When deleted, the corresponding `AuditEntry` retains
  the hash — tamper evidence is preserved while personal data is removed.
- **Attributes:** `id`, `audit_entry_id` (belongs_to AuditEntry), `field_name` (string),
  `value` (string — encrypted at rest), `inserted_at`
- **Actions:** `read`, `create`, `delete_for_player` (GDPR erasure — bulk delete by player_id
  via join to audit entries) — no `update`
- **Paper trail:** no
- **Archival:** no (deletion is the intended operation on erasure)
- **Compliance links:** `RG-UK-GDPR-001`
- **Telemetry prefix:** `[:igaming_ref, :ops, :pii_vault]`

---

## Authentication Resources (always sensitive — added automatically)

#### `IgamingRef.Accounts.User`
- **Type:** Ash resource (`ash_authentication`)
- **Sensitive:** always (not in manifest list — added automatically by classifier)
- **Description:** Authentication subject. Linked to Player record post-registration.
- **Strategies:** password, magic_link
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)

#### `IgamingRef.Accounts.Token`
- **Type:** Ash resource (`ash_authentication`)
- **Sensitive:** always
- **Description:** Authentication tokens (session, magic link, reset).
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)

---

## Transfers (Reactors)

### `IgamingRef.Finance.WithdrawalTransfer`
- **Type:** Reactor + Transfer DSL
- **Description:** Processes an approved withdrawal request through to provider submission.
  Handles balance debit via `IgamingRef.Finance.Transfer` (AshDoubleEntry), ledger recording,
  and provider API call. Fully idempotent. Does NOT call `Wallet.debit` directly — all balance
  mutations go through the Transfer resource.
- **Idempotency key:** `withdrawal_request_id`
- **Steps:** `validate_sufficient_balance`, `check_kyc_verified`, `debit_wallet`,
  `create_ledger_entry`, `submit_to_provider`, `update_withdrawal_status`
  - `check_kyc_verified` — player must have `kyc_status: :verified` (RG-MGA-003)
- **Rules:** `SufficientBalance`, `WithdrawalLimitNotExceeded`, `PlayerNotSelfExcluded`,
  `PlayerKYCVerified`
- **Compliance links:** `RG-UK-014`, `RG-MGA-007`, `RG-MGA-003`
- **Runbook:** `docs/runbooks/withdrawal_transfer.md` *(to be created)*
- **Telemetry prefix:** `[:igaming_ref, :finance, :withdrawal_transfer]`
- **Sensitive:** yes (touches LedgerEntry, Wallet, WithdrawalRequest — all sensitive)

### `IgamingRef.Promotions.BonusGrantTransfer`
- **Type:** Reactor + Transfer DSL
- **Description:** Awards a bonus to a player when campaign eligibility is confirmed.
  Credits wallet and creates `BonusGrant`. Invoked directly or via `BonusEvaluationReactor`.
- **Idempotency key:** `{player_id, campaign_id}`
- **Steps:** `load_context`, `evaluate_rules`, `credit_wallet`,
  `create_ledger_entry`, `create_bonus_grant`
- **Rules:** `PlayerEligibleForCampaign`, `CampaignNotExpired`, `PlayerNotSelfExcluded`
- **Compliance links:** `RG-MGA-005`
- **Runbook:** `docs/runbooks/bonus_grant_transfer.md` *(to be created)*
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_grant_transfer]`
- **Sensitive:** no (touches Wallet/LedgerEntry which are sensitive — classifier escalates to
  `:sensitive` because it touches sensitive resources)

### `IgamingRef.Promotions.BonusEvaluationReactor`
- **Type:** Reactor (non-Transfer) — `reactor` node type
- **Description:** Evaluates `BonusEvent` rows against manager-configured triggers,
  condition groups, conditions, and executions, then runs whitelisted handlers.
- **Idempotency key:** `event_id`
- **Steps:** `load_event`, `load_player`, `load_active_campaigns`,
  `find_matching_campaigns`, `execute_campaigns`, `mark_processed`
- **Runbook:** `docs/runbooks/bonus_evaluation_reactor.md`
- **Compliance links:** `RG-MGA-005`, `RG-UK-011`
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_evaluation_reactor]`

### `IgamingRef.Gaming.ProviderSyncReactor`
- **Type:** Reactor (non-Transfer) — `reactor` node type
- **Description:** Orchestrates a full catalog sync for one provider. Reads
  `ProviderConfig`, resolves the active adapter module via `active_adapter_version`,
  calls `fetch_catalog/1` on the adapter, diffs the response against stored `Game` rows,
  upserts changed games, creates `GameVersion` entries for each diffed field, and marks
  games absent from the provider response as `:unpublished`. Fires the `adapter_verify_failed`
  manifest notification if the adapter returns a non-OK response. Idempotent — safe to
  re-run on retry.
- **Idempotency key:** `{provider_config_id, sync_date}`
- **Steps:** `load_provider_config`, `resolve_adapter_module`, `fetch_catalog`,
  `diff_against_stored`, `upsert_games`, `create_game_versions`, `mark_absent_games`,
  `emit_sync_telemetry`
  - `resolve_adapter_module` — dispatches to versioned adapter using
    `ProviderConfig.active_adapter_version`; emits `adapter_verify_failed` notification
    on HTTP error or unexpected schema
- **Rules:** `ProviderActive`
- **Compliance links:** `RG-MGA-006`, `RG-MGA-011`
- **Runbook:** `docs/runbooks/provider_sync_reactor.md` *(to be created)*
- **Telemetry prefix:** `[:igaming_ref, :gaming, :provider_sync_reactor]`
- **Sensitive:** no

### `IgamingRef.Gaming.CatalogSyncJob`
- **Type:** Oban worker — `job` node type
- **Description:** Per-provider scheduled job. Enqueues `ProviderSyncReactor` for one
  `ProviderConfig` row. Scheduled via cron; also triggerable manually from back-office.
  Unique per `provider_config_id` — duplicate jobs are discarded. The `async` edge in the
  system graph runs from this job to `ProviderSyncReactor`.
- **Oban queue:** `gaming_sync`
- **Unique constraint:** `unique_for: [keys: [:provider_config_id], period: 3600]`
  (one sync per provider per hour maximum)
- **Compliance links:** `RG-MGA-006`
- **Telemetry prefix:** `[:igaming_ref, :gaming, :catalog_sync_job]`

---

## Rules

| Module | Domain | Description | Compliance |
|---|---|---|---|
| `IgamingRef.Finance.Rules.SufficientBalance` | Finance | Wallet balance (derived sum) must cover the requested amount | RG-MGA-001 |
| `IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded` | Finance | Withdrawal amount must not exceed the player's configured daily limit | RG-UK-014, RG-MGA-007 |
| `IgamingRef.Finance.Rules.PlayerKYCVerified` | Finance | Player must have `kyc_status: :verified` before any withdrawal | RG-MGA-003, RG-UK-002 |
| `IgamingRef.Players.Rules.PlayerNotSelfExcluded` | Players | Player must not have an active self-exclusion record | RG-UK-008, RG-MGA-009 |
| `IgamingRef.Promotions.Rules.PlayerEligibleForCampaign` | Promotions | Player meets campaign eligibility criteria | RG-MGA-005 |
| `IgamingRef.Promotions.Rules.CampaignNotExpired` | Promotions | Campaign's `expires_at` has not passed | RG-MGA-005 |
| `IgamingRef.Gaming.Rules.ProviderActive` | Gaming | `ProviderConfig.status` must be `:active` before a sync is permitted | RG-MGA-011 |
| `IgamingRef.Gaming.Rules.GameRTPCertified` | Gaming | `Game.certification_status` must be `:certified` before `publish` is permitted | RG-MGA-006 |

---

## Compliance Requirements

These are the RG-* requirements declared in `docs/regulations/` for the reference project.
Minimum set to make the compliance field of `mix foundry.project.status` non-trivial and the compliance matrix
meaningful across three status states (passing, failing, unimplemented).

| ID | Summary | Implementing module(s) | Status |
|---|---|---|---|
| `RG-MGA-001` | Wallet balance integrity — balance never goes negative; derived from immutable ledger | `Finance.Wallet`, `Finance.LedgerEntry`, `Finance.Transfer`, `Finance.Rules.SufficientBalance` | planned |
| `RG-MGA-002` | Ledger immutability — entries cannot be modified or deleted | `Finance.LedgerEntry` (AshDoubleEntry enforces no update/destroy) | planned |
| `RG-MGA-003` | KYC verification required before first withdrawal | `Players.KYCDocument`, `Finance.Rules.PlayerKYCVerified` (gate in WithdrawalTransfer) | planned |
| `RG-MGA-005` | Bonus terms must be transparent and enforced by configurable runtime logic | `Promotions.BonusCampaign`, `Promotions.BonusTrigger`, `Promotions.BonusCondition`, `Promotions.BonusExecution`, `Promotions.BonusEvaluationReactor`, `Promotions.BonusGrant` | planned |
| `RG-MGA-006` | Published RTP must match the provider-certified value; changes are logged in GameVersion | `Gaming.Game` (certification gate on publish), `Gaming.GameVersion` (RTP change log), `Gaming.Rules.GameRTPCertified` | planned |
| `RG-MGA-007` | Withdrawal processing within declared SLA | `Finance.WithdrawalRequest`, `Finance.WithdrawalTransfer` | planned |
| `RG-MGA-009` | Self-exclusion records must be immutable | `Players.SelfExclusionRecord` | planned |
| `RG-MGA-010` | Audit records retained per regulatory minimum (7 years) | `Ops.AuditEntry` (append-only, no destroy) | planned |
| `RG-MGA-011` | Operator must be able to suspend a provider or game immediately (malfunction response) | `Gaming.ProviderConfig.suspend`, `Gaming.Game.suspend`, `Gaming.Rules.ProviderActive` | planned |
| `RG-UK-002` | Player identity must be verified before account activation | `Players.Player` (kyc_status gate), `Players.KYCDocument` | planned |
| `RG-UK-003` | Player-facing balance must match ledger sum at all times | `Finance.Wallet` (no mutable balance field; derived from LedgerEntry sum), `Finance.LedgerEntry` | planned |
| `RG-UK-004` | UK players must be able to choose wallet draw order | `Players.Player.wallet_draw_order` attribute, `update_draw_order` action | planned |
| `RG-UK-008` | Self-exclusion must block all financial transactions immediately | `Players.Rules.PlayerNotSelfExcluded` (required in all Transfers) | planned |
| `RG-UK-011` | Bonus wagering requirements must be disclosed and enforced at grant time | `Promotions.BonusCampaign`, `Promotions.BonusExecution`, `Promotions.BonusGrant`, `Promotions.BonusEvaluationReactor` | planned |
| `RG-UK-014` | Withdrawals must be processed to original payment method | `Finance.WithdrawalTransfer` | planned |
| `RG-UK-015` | Game categories must be accurate for self-exclusion tooling (some programmes are category-scoped) | `Gaming.Game.category`, `Gaming.GameCatalog.list_by_category` | planned |
| `RG-UK-GDPR-001` | Personal data must be erasable without breaking audit chain integrity | `Ops.AuditEntry`, `Ops.PIIVault` (PIIVault pattern per ADR-006) | planned |

---

## Manifest Configuration (reference project)

```elixir
# reference_projects/igaming/.foundry/manifest.exs
[
  project_name: "IgamingRef",
  domain_type: :igaming,

  sensitive_resources: [
    IgamingRef.Finance.Wallet,
    IgamingRef.Finance.LedgerEntry,
    IgamingRef.Finance.Transfer,
    IgamingRef.Finance.WithdrawalRequest,
    IgamingRef.Gaming.ProviderConfig,
    IgamingRef.Players.Player,
    IgamingRef.Players.KYCDocument,
    IgamingRef.Players.SelfExclusionRecord,
    IgamingRef.Ops.AuditEntry,
    IgamingRef.Ops.PIIVault
    # IgamingRef.Accounts.User and Token are added automatically
  ],

  approvers: [
    sensitive_lead: "finance-lead@igamingref.test",
    sensitive_lead_delegate: "cto@igamingref.test",
    domain_lead: "platform-lead@igamingref.test",
    platform_lead: "platform-lead@igamingref.test",
    compliance_officer: "compliance@igamingref.test"
  ],

  approval_sla: [
    structural:  nil,
    behavioral:  [hours: 24],
    sensitive:   [hours: 4],
    compliance:  [hours: 48]
  ],

  auto_apply_structural: false,
  change_generation_enabled: true,

  notifications: [
    runbook_stale:          [channel: :slack,  target: "#ops-alerts"],
    adapter_verify_failed:  [channel: :email,  target: "platform-lead@igamingref.test"],
    compliance_test_failed: [channel: :slack,  target: "#compliance-alerts"]
  ],

  coverage_gate: false,
  coverage_weights: [
    transfer_coverage:    0.25,
    rule_coverage:        0.20,
    blueprint_coverage:   0.20,
    compliance_coverage:  0.25,
    ui_coverage:          0.10
  ],

  conditional_libraries: [
    :ash_double_entry,
    :ash_money,
    :ash_state_machine,
    :ash_paper_trail,
    :ash_archival,
    :fun_with_flags
  ]
]
```

---

## Expected Module Counts (Phase 1 validation)

`mix foundry.project.context` must return all fixture nodes. Counts by domain and type:

| Domain | Resources | Reactors/Transfers | Jobs | Rules | Providers |
|---|---|---|---|---|---|
| `Finance` | 5 (Wallet, LedgerEntry, Transfer, WithdrawalRequest, WithdrawalWebhookEvent) | 1 (WithdrawalTransfer) | 1 (ProcessWithdrawalWebhook) | 3 (SufficientBalance, WithdrawalLimitNotExceeded, PlayerKYCVerified) | 0 |
| `Players` | 3 (Player, KYCDocument, SelfExclusionRecord) | 0 | 0 | 1 (PlayerNotSelfExcluded) | 0 |
| `Promotions` | 7 (BonusCampaign, BonusGrant, BonusTrigger, BonusConditionGroup, BonusCondition, BonusExecution, BonusEvent) | 2 (BonusGrantTransfer, BonusEvaluationReactor) | 0 | 2 (PlayerEligibleForCampaign, CampaignNotExpired) | 0 |
| `Gaming` | 3 (ProviderConfig, Game, GameVersion) + 1 read-only (GameCatalog) | 1 (ProviderSyncReactor) | 1 (CatalogSyncJob) | 2 (ProviderActive, GameRTPCertified) | 2 (PragmaticPlayV1, PragmaticPlayV2) |
| `Ops` | 2 (AuditEntry, PIIVault) | 0 | 0 | 0 | 0 |
| `Accounts` | 2 (User, Token — auth) | 0 | 0 | 0 | 0 |

**Total:** 23 resources (+ 1 read-only derived), 4 reactors/transfers, 2 jobs, 8 rules,
2 provider adapters, 17 compliance requirements.

---

## Expected Lint Results (Phase 1 validation)

Running `mix foundry.lint.all --json` against a freshly scaffolded reference project
(before tests are written) must produce:

- **Zero** `:missing_description` violations (all attributes and modules have descriptions)
- **Zero** `:missing_paper_trail` violations (all sensitive resources declare AshPaperTrail)
- **Zero** `:missing_archival` violations (all sensitive resources declare AshArchival)
- **Zero** `:missing_idempotency` violations (all Transfers/Reactors with side effects declare idempotency keys)
- **Zero** bonus-engine configuration lint errors for supported trigger/condition/execution
  kinds (unknown kinds rejected at write time by Ash constraints)
- **Zero** `:adapter_missing_contract_tests` violations — both PragmaticPlayV1 and V2
  adapter modules must have contract tests before they can be considered active-eligible
  (INV-010 / ADR-007 constraint)
- **One** `:adapter_version_not_active` warning for PragmaticPlayV2 — registered but not
  set as `active_adapter_version` on any `ProviderConfig` row; this is expected and correct
- **Warnings** for `:missing_notification_config` — not an error (manifest has config, but
  the test channels are non-functional in the test environment by design)
- **At least one** compliance requirement with `status: :planned` (not yet implemented
  E2E test) — to make the compliance matrix show an incomplete state

---

## Phase 1 Acceptance Matrix

This section is the authoritative "done when" contract for Phase 1. Every row must pass
before Phase 2 begins. The ExUnit integration test module `Foundry.Phase1AcceptanceTest`
runs all assertions below against the reference project at `reference_projects/igaming/`.

### `mix foundry.project.context <Module>`

| Assertion | Module under test | Expected |
|---|---|---|
| All schema fields present | `IgamingRef.Finance.WithdrawalTransfer` | `module`, `type`, `domain`, `app`, `description`, `steps`, `rules`, `compliance`, `runbook`, `invariants`, `related_resources`, `adrs`, `last_modified`, `sensitive`, `test_coverage`, `data_layer`, `pending_migrations`, `paper_trail`, `archival`, `state_machine`, `api_routes`, `telemetry_prefix`, `money_attributes`, `authentication_subject`, `oban_queues`, `rate_limited`, `feature_flags`, `agent_steps` |
| `type` field correct | `IgamingRef.Finance.WithdrawalTransfer` | `"transfer"` |
| `sensitive: true` | `IgamingRef.Finance.Wallet` | `true` |
| `sensitive: false` | `IgamingRef.Gaming.Game` | `false` |
| `paper_trail: true` | `IgamingRef.Finance.LedgerEntry` | `true` |
| `archival: true` | `IgamingRef.Finance.LedgerEntry` | `true` |
| `state_machine.present: true` | `IgamingRef.Finance.Wallet` | `true`; states include `"active"`, `"frozen"`, `"closed"` |
| `state_machine.present: false` | `IgamingRef.Finance.LedgerEntry` | `false`; `states: []` |
| `money_attributes` populated | `IgamingRef.Finance.LedgerEntry` | Entry for `amount` with `type: "Ash.Type.Money"` and non-null `cldr_backend` |
| `money_attributes: []` | `IgamingRef.Gaming.Game` | `[]` |
| `authentication_subject: true` | `IgamingRef.Accounts.User` | `true` |
| `pending_migrations: false` | any module | `false` (reference project has no outstanding migrations) |
| `compliance` non-empty | `IgamingRef.Finance.WithdrawalTransfer` | Contains `"RG-UK-014"` and `"RG-MGA-007"` |
| `runbook` declared | `IgamingRef.Finance.WithdrawalTransfer` | `"docs/runbooks/withdrawal_transfer.md"` |
| `rules` non-empty | `IgamingRef.Finance.WithdrawalTransfer` | Contains `"SufficientBalance"`, `"WithdrawalLimitNotExceeded"`, `"PlayerKYCVerified"` |
| `rules: []` | `IgamingRef.Finance.LedgerEntry` | `[]` |
| `app: null` | any module | `null` (standard project, not umbrella) |
| `agent_steps: []` | any module | `[]` (no AshAI agent steps in reference project) |
| Unknown module exits non-zero | `IgamingRef.Finance.DoesNotExist` | Exit code 1, error JSON with `"error": "module_not_found"` |

### `mix foundry.project.context` (bulk)

`mix foundry.context.all` has been absorbed into `mix foundry.project.context`. All node
count assertions from the former `context.all` matrix are now asserted against
`mix foundry.project.context nodes`.

| Assertion | Expected |
|---|---|
| Top-level keys | `generated_at`, `project`, `project_type`, `domain_type`, `nodes`, `edges`, `spec_kit`, `graph_delta` |
| `project` | `"IgamingRef"` |
| `project_type` | `"standard"` |
| `domain_type` | `"igaming"` |
| `graph_delta` | `null` (no active editing session at test time) |
| `nodes` count | 36 (23 resources + 1 read-only + 4 reactors/transfers + 2 jobs + 8 rules + 2 providers + 1 trigger) before synthetic external nodes |
| Nodes ordered | Alphabetical by FQN — assert first node FQN < second node FQN |
| Domain count derived from nodes | 6 (`Finance`, `Players`, `Promotions`, `Gaming`, `Ops`, `Accounts`) |
| `Finance` node count | 10 (5 resources + 1 transfer + 1 job + 3 rules) |
| `Promotions` configurable resources present | `BonusTrigger`, `BonusConditionGroup`, `BonusCondition`, `BonusExecution`, `BonusEvent` |
| `Gaming` provider count | 2 (`PragmaticPlayV1`, `PragmaticPlayV2`) |
| `Gaming` job count | 1 (`CatalogSyncJob`) |
| `Ops` resource count | 2 (`AuditEntry`, `PIIVault`) |
| `Accounts` resource count | 2 (`User`, `Token`) |
| Every node has `id`, `module`, `type`, `domain`, `app: null` | All nodes |
| Sensitive node: `sensitive: true` | Any node in `sensitive_resources` manifest list |
| Non-sensitive node: `sensitive: false` | `IgamingRef.Gaming.Game` |
| `edges` non-empty | At minimum: `WithdrawalTransfer → Wallet (writes)`, `WithdrawalTransfer → LedgerEntry (writes)` |
| Edges ordered | By `from` FQN ascending, then `to` FQN ascending |
| `WithdrawalTransfer → Wallet` edge exists | `relation: "writes"`, `cross_app: false`, `cross_project: false` |
| `WithdrawalTransfer → LedgerEntry` edge exists | `relation: "writes"` |
| `CatalogSyncJob → ProviderSyncReactor` edge exists | `relation: "async"` |
| `cross_app: false` on all edges | All edges (standard project, no umbrella) |
| `spec_kit` field present | Non-null object |
| `spec_kit.adrs` non-empty | At least the reference project's ADRs |
| `spec_kit.runbooks` count | 4 (withdrawal_transfer, bonus_grant_transfer, provider_sync_reactor, bonus_evaluation_reactor) |
| `spec_kit.index_token_count` ≤ 400 | Numeric, ≤ 400 |
| `spec_kit.index_token_warn` | `false` (reference project corpus is small) |

**Token warn path test (synthetic):** Add enough stub documents to `docs/adrs/` to push
`index_token_count` above 360. Assert `spec_kit.index_token_warn: true`. Remove stubs afterward.

### `mix foundry.project.context --check`

| Assertion | Setup | Expected exit code |
|---|---|---|
| Exits 0 when current | `.foundry/context.lock` freshly generated | 0 |
| Exits 1 when source newer | Touch any `lib/` file after generating | 1 |
| Exits 1 when lock absent | Delete `.foundry/context.lock` | 1 |

### `mix foundry.project.status --json`

| Assertion | Expected |
|---|---|
| Top-level keys present | `generated_at`, `compiled_at`, `project`, `domains`, `sensitive_modules`, `lint`, `migrations`, `proposals`, `compliance`, `test_coverage`, `ci`, `stack`, `manifest` |
| `project` | `"IgamingRef"` |
| `domains` | List of 6 domain names |
| `sensitive_modules` | Contains short names matching manifest `sensitive_resources` list |
| `compiled_at` present | Non-null ISO 8601 timestamp |
| `lint.errors` | `0` (clean reference project) |
| `lint.warnings` count | ≥ 1 (`:adapter_version_not_active` for PragmaticPlayV2) |
| `migrations.pending_count` | `0` |
| `proposals.open_count` | `0` |
| `compliance.requirements` | Contains all 17 RG-* IDs from fixture |
| At least one `status: "planned"` in compliance | True (fixture requires this) |
| `stack.ash` non-null | Non-null string starting with `"3."` |
| `stack` version strings | Exact resolved values from `mix.lock`, not constraint expressions |
| `manifest.domain_type` | `"igaming"` |
| `ci.context_lock_current` | `true` (freshly generated lock) |

### `mix foundry.compliance.check` — absorbed into `project.status`

`mix foundry.compliance.check` no longer exists as a standalone task. The full compliance
matrix is the `compliance` field of `mix foundry.project.status`. Compliance assertions
are covered in the `project.status` matrix above.

### `mix foundry.lint.all --json`

| Assertion | Setup | Expected |
|---|---|---|
| Clean run exits 0 | Reference project as scaffolded | Exit 0; `errors: 0` |
| `:missing_runbook` fires | Remove `@runbook` from `WithdrawalTransfer` | Exit 1; violation with `rule: "missing_runbook"`, `module: "IgamingRef.Finance.WithdrawalTransfer"` |
| `:missing_paper_trail` fires | Remove AshPaperTrail from `Wallet` | Exit 1; violation with `rule: "missing_paper_trail"` |
| `:missing_archival` fires | Remove AshArchival from `LedgerEntry` | Exit 1; violation with `rule: "missing_archival"` |
| `:missing_idempotency` fires | Remove idempotency key from `WithdrawalTransfer` | Exit 1; violation with `rule: "missing_idempotency"` |
| `:missing_description` fires | Remove `@moduledoc` from any non-test module | Exit 1 |
| Manifest missing `sensitive_lead` exits 1 | Remove `approvers.sensitive_lead` from manifest | Exit 1; `rule: "manifest_missing_required_approver"` |
| `:ash_version_outdated` does NOT fire | Clean project with Ash 3.x in mix.lock | Rule absent from violations |
| Warnings don't fail CI | `:adapter_version_not_active` warning present | Exit 0 |
| Output is valid JSON | Any run | `Jason.decode!/1` succeeds on stdout |
| Violations include `module`, `rule`, `message`, `severity` | Any violation | All four fields present |
| Violations ordered | Any run with mixed severities | `:error` before `:warning`; alphabetical by module within severity |

### `mix foundry.versions.check` — eliminated

Version constraint enforcement has moved to `Foundry.LintRules.VersionRule` inside
`mix foundry.lint.all`. Version data is in the `stack` field of `mix foundry.project.status`,
sourced from `mix.lock`. There is no standalone versions.check task to test.

### `Foundry.FileSystem.read/2`

| Assertion | Call | Expected |
|---|---|---|
| Permitted path succeeds | `read(root, "lib/igaming_ref/finance/wallet.ex")` | `{:ok, content}` |
| Spec-kit path succeeds | `read(root, "docs/adrs/ADR-003-agent-context-strategy.md")` | `{:ok, content}` |
| `AGENTS.md` succeeds | `read(root, "AGENTS.md")` | `{:ok, content}` |
| `.foundry/manifest.exs` succeeds | `read(root, ".foundry/manifest.exs")` | `{:ok, content}` |
| `_build/` rejected | `read(root, "_build/dev/lib/igaming_ref/ebin/something.beam")` | `{:error, :outside_boundary}` |
| `deps/` rejected | `read(root, "deps/ash/lib/ash.ex")` | `{:error, :outside_boundary}` |
| `.env` rejected | `read(root, ".env")` | `{:error, :outside_boundary}` |
| Path traversal rejected | `read(root, "lib/../../.env")` | `{:error, :outside_boundary}` |
| Double traversal rejected | `read(root, "lib/../lib/../.env")` | `{:error, :outside_boundary}` |
| Non-existent permitted path | `read(root, "lib/does_not_exist.ex")` | `{:error, :not_found}` |

### Integration: CI pipeline simulation

Run in sequence against the reference project. All must pass:

```bash
mix compile --warnings-as-errors
mix foundry.project.context
mix foundry.project.context --check   # must exit 0 (just generated)
mix foundry.lint.all                  # must exit 0 on clean project
mix foundry.project.status
```

Then touch a source file and assert:
```bash
touch lib/igaming_ref/finance/wallet.ex
mix foundry.project.context --check   # must exit 1 (lock hash mismatch)
mix foundry.project.context           # regenerate and update lock
mix foundry.project.context --check   # must exit 0 again
```

**Note:** `mix foundry.versions.check` and `mix foundry.context.all` are eliminated —
version constraints are enforced via `mix foundry.lint.all`, and the node corpus is
available via `mix foundry.project.context`. `mix foundry.compliance.check` is absorbed
into `mix foundry.project.status`. There is no separate
`mix foundry.spec_kit.index --check` step — spec-kit index staleness is enforced via
`mix foundry.project.context --check` (ADR-020).

---

## Runbooks Required

These runbooks are referenced by Transfer and Reactor modules (INV-005) and must exist as files:

- `docs/runbooks/withdrawal_transfer.md` — for `WithdrawalTransfer`
- `docs/runbooks/bonus_grant_transfer.md` — for `BonusGrantTransfer`
- `docs/runbooks/provider_sync_reactor.md` — for `ProviderSyncReactor`

Stub content is sufficient for the reference project. The runbook file just needs to
exist at the declared path — INV-005 lint rule checks file existence, not content quality.

---

## ADR Alignment

Cross-reference of ADR-001 through ADR-010 to their implementing elements in this fixture.
ADRs from Foundry's own spec-kit (ADR-001..017 in `docs/adrs/`) are a separate namespace —
these ADRs are from the iGaming target platform's spec-kit (`Giro` / `IgamingRef`).

| ADR | Decision | Implemented by |
|---|---|---|
| ADR-001 | Double-entry ledger — no mutable balance fields | `Finance.LedgerEntry` (AshDoubleEntry.Balance), `Finance.Wallet` (no `balance` attribute), `Finance.Transfer` |
| ADR-002 | Configurable runtime logic for bonus engine | `Promotions.BonusTrigger`, `Promotions.BonusConditionGroup`, `Promotions.BonusCondition`, `Promotions.BonusExecution`, `Promotions.BonusEvaluationReactor` |
| ADR-003 | Multi-currency account structure | `Finance.Wallet` (one row per currency+bucket; `currency` + `bucket` attributes) |
| ADR-004 | Wallet draw order as player preference | `Players.Player.wallet_draw_order` attribute, `update_draw_order` action, `jurisdiction` field for `:de` override |
| ADR-005 | Bonus terms and outcomes are explicit and auditable | `Promotions.BonusEvent` + configurable condition/execution resources; `BonusGrant` state transitions remain explicit actions |
| ADR-006 | PIIVault pattern for GDPR vs audit log conflict | `Ops.AuditEntry` (hashed PII in state columns), `Ops.PIIVault` (original values, deleted on erasure) |
| ADR-007 | Provider API versioning via Strangler Fig | `Gaming.Adapters.PragmaticPlayV1` and `PragmaticPlayV2` (side-by-side modules); `Gaming.ProviderConfig.active_adapter_version` (dispatch field); `Gaming.ProviderSyncReactor.resolve_adapter_module` step |
| ADR-008 | AshDoubleEntry adoption (not custom ledger) | `Finance.Wallet` extends `AshDoubleEntry.Account`; `Finance.LedgerEntry` extends `AshDoubleEntry.Balance`; `Finance.Transfer` extends `AshDoubleEntry.Transfer` |
| ADR-009 | Presigned S3 upload for KYC documents | `Players.KYCDocument` (state machine, no file content stored), `Players.KYCUploadToken` (presigned URL token) |
| ADR-010 | Affiliate attribution — last-click, operator-configurable | Not in reference project scope (minimum viable fixture). Add `Affiliates` domain when testing affiliate flow. |

---

## What This Document Is Not

This document does not describe the full iGaming business domain. It describes the
*minimum viable reference project* that makes every phase's acceptance criteria testable.
The reference project is a test fixture, not a production system. It is complete enough
to exercise all six Mix tasks, all lint rules, the compliance check, provider adapter
versioning, and catalog aggregation — nothing more.

ADR-010 (affiliate attribution) is deliberately excluded because it requires an `Affiliates`
domain that adds no additional Foundry mechanics not already covered by the Gaming domain.
