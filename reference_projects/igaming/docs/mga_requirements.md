# IgamingRef Regulations — Malta Gaming Authority (MGA)
#
# These requirements are parsed by `mix foundry.compliance.check`.
# Format: ### RG-<JURISDICTION>-<NNN> heading, then Summary/Implementation/Test tag lines.

---

### RG-MGA-001
**Summary:** Wallet balance integrity — balance must never go negative
**Implementation:** `IgamingRef.Finance.Wallet`, `IgamingRef.Finance.LedgerEntry`, `IgamingRef.Finance.Rules.SufficientBalance`
**Test tag:** `:rg_mga_001`
**Status:** planned

### RG-MGA-002
**Summary:** Ledger immutability — entries cannot be modified or deleted after creation
**Implementation:** `IgamingRef.Finance.LedgerEntry`
**Test tag:** `:rg_mga_002`
**Status:** planned

### RG-MGA-003
**Summary:** KYC verification required before first withdrawal is permitted
**Implementation:** `IgamingRef.Players.Player`
**Test tag:** `:rg_mga_003`
**Status:** planned

### RG-MGA-005
**Summary:** Bonus terms must be transparent and enforced at grant time
**Implementation:** `IgamingRef.Promotions.BonusCampaign`, `IgamingRef.Promotions.BonusGrant`, `IgamingRef.Promotions.Rules.PlayerEligibleForCampaign`
**Test tag:** `:rg_mga_005`
**Status:** planned

### RG-MGA-007
**Summary:** Withdrawal requests must be processed within the declared SLA
**Implementation:** `IgamingRef.Finance.WithdrawalRequest`, `IgamingRef.Finance.WithdrawalTransfer`
**Test tag:** `:rg_mga_007`
**Status:** planned

### RG-MGA-009
**Summary:** Self-exclusion records must be immutable — they cannot be deleted
**Implementation:** `IgamingRef.Players.SelfExclusionRecord`
**Test tag:** `:rg_mga_009`
**Status:** planned