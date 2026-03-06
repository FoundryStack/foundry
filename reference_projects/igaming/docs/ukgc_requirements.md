# IgamingRef Regulations — UK Gambling Commission (UKGC)

---

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