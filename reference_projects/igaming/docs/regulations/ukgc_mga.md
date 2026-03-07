# IgamingRef Regulations — UKGC & MGA

---

### RG-MGA-001
**Summary:** Wallet balance integrity - balance never goes negative
**Implementation:** `IgamingRef.Finance.Wallet`, `IgamingRef.Finance.LedgerEntry`, `IgamingRef.Finance.Rules.SufficientBalance`
**Test tag:** `:rg_mga_001`
**Status:** planned

### RG-MGA-002
**Summary:** Ledger immutability - entries cannot be modified or deleted
**Implementation:** `IgamingRef.Finance.LedgerEntry`
**Test tag:** `:rg_mga_002`
**Status:** planned

### RG-MGA-003
**Summary:** KYC verification required before first withdrawal
**Implementation:** `IgamingRef.Players.Player`
**Test tag:** `:rg_mga_003`
**Status:** planned

### RG-MGA-005
**Summary:** Bonus terms must be transparent and enforced
**Implementation:** `IgamingRef.Promotions.BonusCampaign`, `IgamingRef.Promotions.BonusGrant`, `IgamingRef.Promotions.Rules.PlayerEligibleForCampaign`
**Test tag:** `:rg_mga_005`
**Status:** planned

### RG-MGA-007
**Summary:** Withdrawal processing within declared SLA
**Implementation:** `IgamingRef.Finance.WithdrawalRequest`, `IgamingRef.Finance.WithdrawalTransfer`
**Test tag:** `:rg_mga_007`
**Status:** planned

### RG-MGA-009
**Summary:** Self-exclusion records must be immutable
**Implementation:** `IgamingRef.Players.SelfExclusionRecord`
**Test tag:** `:rg_mga_009`
**Status:** planned

### RG-UK-002
**Summary:** Player identity must be verified before account activation is permitted
**Implementation:** `IgamingRef.Players.Player`
**Test tag:** `:rg_uk_002`
**Status:** planned

### RG-UK-003
**Summary:** Player-facing balance must match the sum of all ledger entries at all times
**Implementation:** `IgamingRef.Finance.Wallet`, `IgamingRef.Finance.LedgerEntry`
**Test tag:** `:rg_uk_003`
**Status:** planned

### RG-UK-008
**Summary:** Self-exclusion must block all financial transactions immediately upon activation
**Implementation:** `IgamingRef.Players.Rules.PlayerNotSelfExcluded`
**Test tag:** `:rg_uk_008`
**Status:** planned

### RG-UK-011
**Summary:** Bonus wagering requirements must be disclosed to the player at grant time
**Implementation:** `IgamingRef.Promotions.BonusCampaign`, `IgamingRef.Promotions.BonusGrant`
**Test tag:** `:rg_uk_011`
**Status:** planned

### RG-UK-014
**Summary:** Withdrawals must be processed to the player's original payment method
**Implementation:** `IgamingRef.Finance.WithdrawalTransfer`
**Test tag:** `:rg_uk_014`
**Status:** planned
