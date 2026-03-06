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

The reference project has three domains. This is the minimum to make the system map
non-trivial (multiple clusters), the compliance matrix meaningful, and the coverage
formula exercise all five dimensions.

| Domain module | Purpose |
|---|---|
| `IgamingRef.Finance` | Ledger, wallets, transfers — the financial core |
| `IgamingRef.Players` | Player accounts, KYC, self-exclusion |
| `IgamingRef.Promotions` | Bonus campaigns, blueprints, wagering |

---

## Resources

### `IgamingRef.Finance` domain

#### `IgamingRef.Finance.Wallet`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Holds a player's current balance across currency denominations
- **Attributes:** `id`, `player_id` (belongs_to Players.Player), `currency` (string), `balance` (`Ash.Type.Money`), `status` (atom: `:active | :frozen | :closed`), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `credit`, `debit`, `freeze`, `close`
- **State machine:** yes — states: `:active`, `:frozen`, `:closed`; transitions: `freeze` (active→frozen), `unfreeze` (frozen→active), `close` (active|frozen→closed)
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012) — soft delete only
- **Compliance links:** `RG-MGA-001` (wallet integrity), `RG-UK-003` (balance accuracy)
- **Rate limited:** yes (debit action)
- **Telemetry prefix:** `[:igaming_ref, :finance, :wallet]`

#### `IgamingRef.Finance.LedgerEntry`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Immutable record of every financial movement. Append-only by policy.
- **Attributes:** `id`, `wallet_id` (belongs_to Wallet), `amount` (`Ash.Type.Money`), `direction` (atom: `:credit | :debit`), `kind` (atom: `:deposit | :withdrawal | :bonus | :wager | :win | :reversal`), `idempotency_key` (string, unique), `reference_id` (string), `inserted_at`
- **Actions:** `read`, `create` — no update, no destroy (policy enforced)
- **State machine:** no
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-MGA-001`, `RG-MGA-002` (ledger immutability), `RG-UK-003`
- **Telemetry prefix:** `[:igaming_ref, :finance, :ledger_entry]`

#### `IgamingRef.Finance.WithdrawalRequest`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** A player's request to withdraw funds. Goes through approval and provider routing.
- **Attributes:** `id`, `player_id`, `wallet_id`, `amount` (`Ash.Type.Money`), `status` (atom: `:pending | :approved | :processing | :completed | :rejected | :cancelled`), `provider` (string), `provider_reference` (string, nullable), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `approve`, `reject`, `cancel`, `mark_processing`, `mark_completed`
- **State machine:** yes — states mirror status attribute
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-014` (withdrawal processing), `RG-MGA-007` (withdrawal limits)
- **Telemetry prefix:** `[:igaming_ref, :finance, :withdrawal_request]`

---

### `IgamingRef.Players` domain

#### `IgamingRef.Players.Player`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes (PII-bearing)
- **Description:** A registered player account. The root of all player-scoped data.
- **Attributes:** `id`, `email` (string, unique), `username` (string, unique), `date_of_birth` (date), `country_code` (string), `kyc_status` (atom: `:unverified | :pending | :verified | :rejected`), `risk_level` (atom: `:low | :medium | :high`), `status` (atom: `:active | :suspended | :self_excluded | :closed`), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `update_kyc_status`, `suspend`, `self_exclude`, `close`
- **State machine:** yes — status states; transitions: `suspend` (active→suspended), `reinstate` (suspended→active), `self_exclude` (active→self_excluded), `close` (active|suspended→closed)
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-002` (player verification), `RG-MGA-003` (KYC requirements), `RG-UK-008` (self-exclusion)
- **Rate limited:** no
- **Telemetry prefix:** `[:igaming_ref, :players, :player]`

#### `IgamingRef.Players.SelfExclusionRecord`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** yes
- **Description:** Immutable record of a self-exclusion event. Append-only.
- **Attributes:** `id`, `player_id`, `excluded_at`, `exclusion_type` (atom: `:temporary | :permanent`), `duration_days` (integer, nullable), `reinstated_at` (nullable), `inserted_at`
- **Actions:** `read`, `create`, `mark_reinstated` — no destroy
- **Paper trail:** required (INV-011)
- **Archival:** required (INV-012)
- **Compliance links:** `RG-UK-008`, `RG-MGA-009` (self-exclusion integrity)
- **Telemetry prefix:** `[:igaming_ref, :players, :self_exclusion_record]`

---

### `IgamingRef.Promotions` domain

#### `IgamingRef.Promotions.BonusCampaign`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** no
- **Description:** A configured bonus campaign. Declares eligibility rules, amounts, and wagering requirements.
- **Attributes:** `id`, `name` (string), `kind` (atom: `:deposit_match | :free_spins | :cashback`), `status` (atom: `:draft | :active | :paused | :expired`), `eligibility_rule` (string — module name reference), `bonus_amount` (`Ash.Type.Money`), `wagering_multiplier` (decimal), `max_redemptions` (integer, nullable), `starts_at` (datetime), `expires_at` (datetime), `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `update`, `activate`, `pause`, `expire`
- **State machine:** yes — status states
- **Paper trail:** no (not sensitive)
- **Archival:** no
- **Compliance links:** `RG-MGA-005` (bonus terms transparency), `RG-UK-011` (bonus wagering disclosure)
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_campaign]`

#### `IgamingRef.Promotions.BonusGrant`
- **Type:** Ash resource (`ash_postgres`)
- **Sensitive:** no
- **Description:** A specific bonus awarded to a player from a campaign.
- **Attributes:** `id`, `player_id`, `campaign_id`, `amount` (`Ash.Type.Money`), `wagering_remaining` (decimal), `status` (atom: `:active | :wagered | :forfeited | :expired`), `granted_at`, `expires_at`, `inserted_at`, `updated_at`
- **Actions:** `read`, `create`, `apply_wager`, `forfeit`, `expire`, `complete`
- **State machine:** yes — status states
- **Paper trail:** no
- **Archival:** no
- **Compliance links:** `RG-MGA-005`, `RG-UK-011`
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_grant]`

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
- **Description:** Processes an approved withdrawal request through to provider submission. Handles balance debit, ledger recording, and provider API call. Fully idempotent.
- **Idempotency key:** `withdrawal_request_id`
- **Steps:** `validate_sufficient_balance`, `debit_wallet`, `create_ledger_entry`, `submit_to_provider`, `update_withdrawal_status`
- **Rules:** `SufficientBalance`, `WithdrawalLimitNotExceeded`, `PlayerNotSelfExcluded`
- **Compliance links:** `RG-UK-014`, `RG-MGA-007`
- **Runbook:** `docs/runbooks/withdrawal_transfer.md` *(to be created)*
- **Telemetry prefix:** `[:igaming_ref, :finance, :withdrawal_transfer]`
- **Sensitive:** yes (touches LedgerEntry, Wallet, WithdrawalRequest — all sensitive)

### `IgamingRef.Promotions.BonusGrantTransfer`
- **Type:** Reactor + Transfer DSL
- **Description:** Awards a bonus to a player when campaign eligibility is confirmed. Credits wallet and creates grant record. Idempotent.
- **Idempotency key:** `{player_id, campaign_id}`
- **Steps:** `check_eligibility`, `check_campaign_active`, `credit_wallet`, `create_ledger_entry`, `create_bonus_grant`
- **Rules:** `PlayerEligibleForCampaign`, `CampaignNotExpired`, `PlayerNotSelfExcluded`
- **Compliance links:** `RG-MGA-005`
- **Runbook:** `docs/runbooks/bonus_grant_transfer.md` *(to be created)*
- **Telemetry prefix:** `[:igaming_ref, :promotions, :bonus_grant_transfer]`
- **Sensitive:** no (touches Wallet/LedgerEntry which are sensitive — but the Transfer itself is classified by its rule set, not its resources. Classifier will escalate to :sensitive because it touches sensitive resources.)

---

## Rules

| Module | Domain | Description | Compliance |
|---|---|---|---|
| `IgamingRef.Finance.Rules.SufficientBalance` | Finance | Wallet balance must cover the requested amount | RG-MGA-001 |
| `IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded` | Finance | Withdrawal amount must not exceed the player's configured daily limit | RG-UK-014, RG-MGA-007 |
| `IgamingRef.Players.Rules.PlayerNotSelfExcluded` | Players | Player must not have an active self-exclusion record | RG-UK-008, RG-MGA-009 |
| `IgamingRef.Promotions.Rules.PlayerEligibleForCampaign` | Promotions | Player meets the campaign's eligibility criteria | RG-MGA-005 |
| `IgamingRef.Promotions.Rules.CampaignNotExpired` | Promotions | Campaign's expires_at has not passed | RG-MGA-005 |

---

## Compliance Requirements

These are the RG-* requirements declared in `docs/regulations/` for the reference project.
Minimum set to make `mix foundry.compliance.check` non-trivial and the compliance matrix
meaningful across three status states (passing, failing, unimplemented).

| ID | Summary | Implementing module(s) | Status |
|---|---|---|---|
| `RG-MGA-001` | Wallet balance integrity — balance never goes negative | `Finance.Wallet`, `Finance.LedgerEntry`, `Finance.Rules.SufficientBalance` | planned |
| `RG-MGA-002` | Ledger immutability — entries cannot be modified or deleted | `Finance.LedgerEntry` (policy: no update/destroy) | planned |
| `RG-MGA-003` | KYC verification required before first withdrawal | `Players.Player` (kyc_status check in WithdrawalTransfer) | planned |
| `RG-MGA-005` | Bonus terms must be transparent and enforced | `Promotions.BonusCampaign`, `Promotions.BonusGrant`, `Promotions.Rules.PlayerEligibleForCampaign` | planned |
| `RG-MGA-007` | Withdrawal processing within declared SLA | `Finance.WithdrawalRequest`, `Finance.WithdrawalTransfer` | planned |
| `RG-MGA-009` | Self-exclusion records must be immutable | `Players.SelfExclusionRecord` | planned |
| `RG-UK-002` | Player identity must be verified before account activation | `Players.Player` (kyc_status gate) | planned |
| `RG-UK-003` | Player-facing balance must match ledger sum at all times | `Finance.Wallet`, `Finance.LedgerEntry` | planned |
| `RG-UK-008` | Self-exclusion must block all financial transactions immediately | `Players.Rules.PlayerNotSelfExcluded` (in all Transfers) | planned |
| `RG-UK-011` | Bonus wagering requirements must be disclosed at grant time | `Promotions.BonusCampaign`, `Promotions.BonusGrant` | planned |
| `RG-UK-014` | Withdrawals must be processed to original payment method | `Finance.WithdrawalTransfer` | planned |

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
    IgamingRef.Finance.WithdrawalRequest,
    IgamingRef.Players.Player,
    IgamingRef.Players.SelfExclusionRecord
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
    :ash_money,
    :ash_state_machine,
    :fun_with_flags
  ]
]
```

---

## Expected `mix foundry.context.all` Output Shape

Running `mix foundry.context.all --json` against the reference project must return
modules grouped by domain. Summary counts (for Phase 1 acceptance validation):

| Domain | Resources | Transfers | Rules |
|---|---|---|---|
| `Finance` | 3 (Wallet, LedgerEntry, WithdrawalRequest) | 1 (WithdrawalTransfer) | 2 (SufficientBalance, WithdrawalLimitNotExceeded) |
| `Players` | 2 (Player, SelfExclusionRecord) | 0 | 1 (PlayerNotSelfExcluded) |
| `Promotions` | 2 (BonusCampaign, BonusGrant) | 1 (BonusGrantTransfer) | 2 (PlayerEligibleForCampaign, CampaignNotExpired) |
| `Accounts` | 2 (User, Token — auth) | 0 | 0 |

**Total:** 9 resources, 2 transfers, 5 rules, 11 compliance requirements.

---

## Expected Lint Results (Phase 1 validation)

Running `mix foundry.lint.all --json` against a freshly scaffolded reference project
(before tests are written) must produce:

- **Zero** `:missing_description` violations (all attributes and modules have descriptions)
- **Zero** `:missing_paper_trail` violations (all sensitive resources declare AshPaperTrail)
- **Zero** `:missing_archival` violations (all sensitive resources declare AshArchival)
- **Zero** `:missing_idempotency` violations (both Transfers declare idempotency keys)
- **Warnings** for `:missing_notification_config` — not an error (manifest has config, but
  the test channels are non-functional in the test environment by design)
- **At least one** compliance requirement with `status: :planned` (not yet implemented
  E2E test) — to make the compliance matrix show an incomplete state

---

## Runbooks Required

These runbooks are referenced by Transfer modules (INV-005) and must exist as files:

- `docs/runbooks/withdrawal_transfer.md` — for `WithdrawalTransfer`
- `docs/runbooks/bonus_grant_transfer.md` — for `BonusGrantTransfer`

Stub content is sufficient for the reference project. The runbook file just needs to
exist at the declared path — INV-005 lint rule checks file existence, not content quality.

---

## What This Document Is Not

This document does not describe the full iGaming business domain. It describes the
*minimum viable reference project* that makes every phase's acceptance criteria testable.
The reference project is a test fixture, not a production system. It is complete enough
to exercise all six Mix tasks, all lint rules, and the compliance check — nothing more.