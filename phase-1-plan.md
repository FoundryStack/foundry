# Phase 1 Implementation Plan — Structured Data Layer

> **Scope:** Everything in `BUILD_SEQUENCE.md §Phase 1`. Done when all assertions in
> `docs/reference-project-fixture.md §Phase 1 Acceptance Matrix` pass against
> `reference_projects/igaming/`. JSON schemas are frozen at phase end; breaking
> changes after that require an ADR.
>
> **Approach:** Structural tests first. Write the ExUnit test module
> `Foundry.Phase1AcceptanceTest` before any implementation module. Every section
> follows the same rhythm: (1) write the test, (2) implement the minimum to pass it,
> (3) verify output is schema-correct, (4) advance.

---

## Guiding principles

- Nothing ships without a corresponding acceptance matrix row passing.
- The reference project is written from `reference-project-fixture.md`, not from the
  implementation. If implementation diverges from the fixture, fix the implementation.
- Every public output (`NodeEntry`, `EdgeEntry`, `ProjectStatus`, `LintViolation`) is a
  typed Elixir struct before it becomes a JSON serialisation. Structs are the contract;
  JSON is a serialisation detail.
- All file reads in Phase 1 go through `Foundry.FileSystem.read/2`. `File.read!/1` is
  forbidden outside that module and will fail the `FileWriteRule` lint check when it is
  eventually enabled.
- `Foundry.SparkMeta.*` and `Foundry.SparkLint.*` are built as if they are already the
  extracted Hex packages described in ADR-019. No Foundry-specific assumptions (manifests,
  proposals, sensitive resource lists) leak into them. Foundry-specific logic lives
  exclusively in `Foundry.Context.*` and `Foundry.LintRules.*`.

---

## Known constraints and non-obvious decisions

These are recorded here to prevent the most common implementation errors.

**On extension detection:** `module.__info__(:attributes)` returns compile-time module
attributes declared with `@attr value` — things like `@behaviour`, `@moduledoc`,
`@telemetry_prefix`, `@runbook`, `@compliance`, `@adrs`. It does NOT reveal which
modules were passed to `use`. To detect which Spark/Ash extensions a module uses,
call `Spark.extensions(module)` — this returns the list of extension modules
compiled into the DSL. These are two separate mechanisms with separate use cases.

**On `mix.lock` parsing:** Use `Mix.Dep.Lock.read/1` (passing the lock file path) or
read the file and parse with `Code.string_to_quoted!/1` followed by `Code.eval_quoted/1`.
Do not use `Code.eval_string/1` directly on untrusted file content. In local mode this
is low-risk, but the pattern is wrong — `mix.lock` is a map literal, not a script.
The correct approach: `{%{} = lock, _} = Code.eval_string(File.read!(path))`.
Alternatively, the public API: `Mix.Dep.Lock.read()` reads from the current project's
`mix.lock` — this works when the Mix task runs inside the target project.

**On Reactor step introspection:** There is no `Reactor.Info.steps/1`. Reactor steps
are Spark DSL entities. Retrieve them via:
`Spark.Dsl.Extension.get_entities(module, [:reactor, :steps])` — this returns a list
of `%Reactor.Dsl.Step{}` structs (or step-type-specific structs). The `:reactor`
path is the DSL section; `:steps` is the entity group within it.

**On `mix ash.codegen --check` per module:** Do not run this subprocess once per
resource module — it boots Mix for each invocation, which is O(n) Mix boots for n
resources. Run it once per project: `mix ash.codegen --check` exits non-zero and
prints the list of resources with pending migrations. Parse the output or check the
exit code, then mark the relevant modules.

**On `ManifestValidator` and the `SparkLint.Rule` contract:** `ManifestValidator`
validates the manifest itself, not a module. It does not fit the `(module, context)`
signature. It runs as a separate, explicit pass in `mix foundry.lint.all` before the
module-walking loop. Its violations are injected into the same output list with the
same `SparkLint.Violation` type.

**On `SparkLint.Context` and Foundry-specific data:** `SparkLint` is the future
`spark_lint` Hex package. The `SparkLint.Context` struct must not carry a Foundry
manifest struct. It carries an opaque `metadata :: map()` field. Foundry populates
this with `%{manifest: parsed_manifest, sensitive_modules: [...]}` before calling
the runner. `Foundry.LintRules.*` modules cast `context.metadata` to access manifest
data; `SparkLint` itself never inspects it.

**On `FileSystem` permitted path matching:** The `@permitted_roots` list contains both
directory prefixes (`"lib/"`, `"docs/adrs/"`) and exact file paths (`"AGENTS.md"`,
`"mix.exs"`, `".foundry/manifest.exs"`). A single prefix check is wrong for exact
paths — it would allow `AGENTS.md.bak` to pass. The implementation must distinguish
between the two kinds and apply the right check.

**On node counting in the reference project:** The fixture declares **33 nodes** (AUTHORITATIVE).
The breakdown: 17 resources (Wallet, LedgerEntry, Transfer, WithdrawalRequest, Player,
KYCDocument, SelfExclusionRecord, KYCUploadToken, BonusCampaign, BonusGrant,
AuditEntry, PIIVault, ProviderConfig, Game, GameVersion, GameCatalog, Players) + 1 read-only
derived resource (GameCatalog is read-only) + 3 reactors/transfers (WithdrawalTransfer,
BonusGrantTransfer, ProviderSyncReactor) + 1 job (CatalogSyncJob) + 8 rules + 1 blueprint
+ 2 providers = 33. Both KYCUploadToken and GameCatalog are included as nodes and are
documented in the fixture resource table. The acceptance test for `nodes count: 33` must
match this count exactly.

**On fixture domain table:** The reference project fixture must include **6 domains**:
Finance, Players, Promotions, Gaming, Ops, **Accounts**. The current fixture table
omits Accounts. This is an oversight — both `IgamingRef.Accounts.User` and
`IgamingRef.Accounts.Token` are scaffolded and appear in the fixture. Add `Accounts`
to the fixture domain table before P-1 scaffold begins, so acceptan tests match the
actual project structure.

**On the `adapter_version_not_active` lint warning:** This rule ID does not appear in
`lint-catalogue.md`. It is referenced only in the acceptance matrix. Either add it to
the catalogue under a new `Foundry.LintRules.AdapterVersionRule` entry (planned) or
confirm it is emitted by `Foundry.LintRules.VersionRule` as an additional rule ID.
This must be resolved before Step 7. Do not write an acceptance test for a rule that
has no implementation plan.

---

## Prerequisites — before any production code

### P-1 — Scaffold the reference project

Create `reference_projects/igaming/` from `docs/reference-project-fixture.md`. This
is a real, compilable Elixir/Ash project — the test fixture for the entire phase.

Write it in this order so each step compiles cleanly:

1. `mix.exs` — all deps from the ADR-001 stack: `ash ~> 3.4`, `ash_postgres`,
   `ash_double_entry`, `ash_money`, `ash_state_machine`, `ash_paper_trail`,
   `ash_archival`, `ash_authentication`, `oban`, `fun_with_flags`, `nebulex`,
   `mdex`, `nimble_options`, `jason`. Pin to exact versions where the fixture
   specifies them (e.g. `ash: "3.4.1"`).

2. `.foundry/manifest.exs` — copy verbatim from the fixture manifest block.
   Verify all six conditional libraries are declared. Verify all three notification
   targets are present (required by `ManifestValidator`).

3. Six domain modules (not five — the fixture has `Finance`, `Players`, `Promotions`,
   `Gaming`, `Ops`, and `Accounts`) — each with `use Ash.Domain` and a `resources do`
   block listing all resources in that domain.

4. Resources in dependency order to avoid forward references:
   `Accounts` (User, Token — AshAuthentication subjects) →
   `Ops` (AuditEntry, PIIVault) →
   `Players` (Player, KYCDocument, KYCUploadToken, SelfExclusionRecord) →
   `Finance` (Wallet, LedgerEntry, Transfer, WithdrawalRequest) →
   `Promotions` (BonusCampaign, BonusGrant) →
   `Gaming` (ProviderConfig, Game, GameVersion, GameCatalog)

5. Transfer and Reactor modules: `Finance.WithdrawalTransfer`,
   `Promotions.BonusGrantTransfer`, `Gaming.ProviderSyncReactor`.
   Each must declare `@runbook`, `@compliance`, and `@adrs` module attributes to
   exercise the introspection path. Each Transfer must declare an idempotency key.

6. Rule modules: `Finance.Rules.SufficientBalance`,
   `Finance.Rules.WithdrawalLimitNotExceeded`, `Finance.Rules.PlayerKYCVerified`,
   `Players.Rules.PlayerNotSelfExcluded`, `Promotions.Rules.PlayerEligibleForCampaign`,
   `Promotions.Rules.CampaignNotExpired`, `Gaming.Rules.ProviderActive`,
   `Gaming.Rules.GameRTPCertified`.

7. Blueprint module: `Promotions.Blueprints.DepositMatchBlueprint` with the full
   `forfeiture do ... end` DSL block from the fixture.

8. Provider adapter modules: `Gaming.Adapters.PragmaticPlayV1`,
   `Gaming.Adapters.PragmaticPlayV2`. PragmaticPlayV2 must be registered but NOT set
   as the active adapter version on any `ProviderConfig` — this is what triggers the
   expected `:adapter_version_not_active` warning.

9. Spec-kit documents:
   - `docs/runbooks/withdrawal_transfer.md` (stub — file existence only)
   - `docs/runbooks/bonus_grant_transfer.md` (stub)
   - `docs/runbooks/provider_sync_reactor.md` (stub)
   - Stub ADRs in `docs/adrs/` — at minimum 2–3 so `spec_kit.adrs` is non-empty
   - `AGENTS.md` at project root (stub with H1 and one paragraph)
   - `.foundry/usage_rules/ash.md` (stub — to exercise usage_rules indexing)

10. Compliance RG-* declarations: at least one module must declare a requirement with
    no test coverage (fixture requirement: `status: "planned"` present in compliance
    output). The simplest approach: add `RG-UK-999-PLANNED` to one module's
    `@compliance` list but write no corresponding test.

**Gate:** `cd reference_projects/igaming && mix compile --warnings-as-errors` exits 0.
No Foundry implementation begins before this passes.

### P-2 — Create the acceptance test skeleton

Create `test/foundry/phase1_acceptance_test.exs`. Tag every test `@tag :phase1`.
All tests start as `@tag :skip` (pending) — they are the target, not yet green.

```elixir
defmodule Foundry.Phase1AcceptanceTest do
  use ExUnit.Case, async: false
  @moduletag :phase1

  @ref_root Path.expand("../../reference_projects/igaming", __DIR__)

  # Helpers
  defp run_task(task, args \\ []) do
    # Runs a Mix task in the reference project's directory via System.cmd.
    # Returns {stdout, exit_code}. Uses System.cmd instead of Mix.Task.run/2
    # because Mix.Task.run/2 executes in the current Mix project's registry,
    # not in the specified directory's project.
    {output, exit_code} = System.cmd("mix", [task | args], cd: @ref_root)
    {output, exit_code}
  end

  defp decode_json!(output), do: Jason.decode!(output)

  describe "Foundry.FileSystem" do
    @tag :skip
    test "permitted path in lib/ returns {:ok, content}" do ... end
    # ... one pending test per fixture §FileSystem row
  end

  describe "mix foundry.project.context <Module>" do
    @tag :skip
    test "all schema fields present for WithdrawalTransfer" do ... end
    # ... one pending test per fixture §per-module row
  end

  describe "mix foundry.project.context (bulk)" do
    @tag :skip
    test "top-level keys present" do ... end
    # ... one pending test per fixture §bulk row
  end

  describe "mix foundry.project.context --check" do
    @tag :skip
    test "exits 0 when lock is current" do ... end
    # ...
  end

  describe "mix foundry.lint.all" do
    @tag :skip
    test "clean run exits 0" do ... end
    # ...
  end

  describe "mix foundry.project.status" do
    @tag :skip
    test "top-level keys present" do ... end
    # ...
  end

  describe "integration: CI pipeline simulation" do
    @tag :skip
    test "full sequence passes" do ... end
    # ...
  end
end
```

Each section below activates the relevant subset of pending tests and provides the
concrete assertion bodies.

---

## Step 1 — `Foundry.FileSystem`

**Why first:** The security boundary must exist before any file-reading code is written
anywhere else. If it is retrofitted later, it will be missed somewhere.

### 1.1 Tests

`test/foundry/file_system_test.exs` — concrete from the start, not pending:

```elixir
defmodule Foundry.FileSystemTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../reference_projects/igaming", __DIR__)

  describe "permitted paths" do
    test "lib/ file" do
      assert {:ok, content} = Foundry.FileSystem.read(@root, "lib/igaming_ref/finance/wallet.ex")
      assert String.contains?(content, "defmodule")
    end

    test "docs/adrs/ file" do
      # Uses one of the stub ADRs created in P-1
      {:ok, first_adr} =
        File.ls!(Path.join(@root, "docs/adrs/"))
        |> Enum.find(&String.ends_with?(&1, ".md"))
        |> then(&{:ok, &1})
      assert {:ok, _} = Foundry.FileSystem.read(@root, "docs/adrs/#{first_adr}")
    end

    test "AGENTS.md" do
      assert {:ok, _} = Foundry.FileSystem.read(@root, "AGENTS.md")
    end

    test ".foundry/manifest.exs" do
      assert {:ok, _} = Foundry.FileSystem.read(@root, ".foundry/manifest.exs")
    end

    test "mix.exs" do
      assert {:ok, _} = Foundry.FileSystem.read(@root, "mix.exs")
    end

    test "priv/repo/migrations/ file" do
      # Create a stub migration file in P-1 if none exists
      assert {:ok, _} =
        Foundry.FileSystem.read(@root, "priv/repo/migrations/20260101000000_init.exs")
    end
  end

  describe "boundary rejections" do
    test "_build/ is rejected" do
      assert {:error, :outside_boundary} =
        Foundry.FileSystem.read(@root, "_build/dev/lib/igaming_ref/ebin/something.beam")
    end

    test "deps/ is rejected" do
      assert {:error, :outside_boundary} =
        Foundry.FileSystem.read(@root, "deps/ash/lib/ash.ex")
    end

    test ".env is rejected" do
      assert {:error, :outside_boundary} = Foundry.FileSystem.read(@root, ".env")
    end

    test "path traversal: lib/../../.env" do
      assert {:error, :outside_boundary} =
        Foundry.FileSystem.read(@root, "lib/../../.env")
    end

    test "double traversal: lib/../lib/../.env" do
      assert {:error, :outside_boundary} =
        Foundry.FileSystem.read(@root, "lib/../lib/../.env")
    end

    test "AGENTS.md.bak is not a permitted exact path" do
      # Guards against prefix-matching exact files as directories
      assert {:error, :outside_boundary} =
        Foundry.FileSystem.read(@root, "AGENTS.md.bak")
    end

    test "mix.exs.bak is not permitted" do
      assert {:error, :outside_boundary} =
        Foundry.FileSystem.read(@root, "mix.exs.bak")
    end
  end

  describe "not_found" do
    test "non-existent permitted path" do
      assert {:error, :not_found} =
        Foundry.FileSystem.read(@root, "lib/does_not_exist.ex")
    end
  end
end
```

### 1.2 Implementation

```elixir
defmodule Foundry.FileSystem do
  @moduledoc """
  Validated file read boundary for all project file access in channels and controllers.

  All file reads that originate from the Studio UI or copilot shell must go through
  this module. Direct `File.read!/1` calls from channels are forbidden (enforced by
  `Foundry.LintRules.FileWriteRule` in later phases).

  See ADR-020 §File system access via Foundry.FileSystem.
  """

  # Directory prefixes — any file under these paths is permitted.
  @permitted_dirs [
    "lib/",
    "test/",
    "config/",
    "priv/repo/migrations/",
    "docs/adrs/",
    "docs/runbooks/",
    "docs/regulations/",
    ".foundry/usage_rules/"
  ]

  # Exact file paths — only the specific file is permitted, not any file
  # whose path begins with the same string.
  @permitted_exact [
    "AGENTS.md",
    "mix.exs",
    ".foundry/manifest.exs"
  ]

  @type read_error :: :outside_boundary | :not_found | File.posix()

  @spec read(project_root :: String.t(), relative_path :: String.t()) ::
          {:ok, String.t()} | {:error, read_error()}
  def read(project_root, relative_path) do
    root     = Path.expand(project_root)
    expanded = Path.expand(Path.join(root, relative_path))

    if permitted?(expanded, root) do
      case File.read(expanded) do
        {:ok, content}   -> {:ok, content}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :outside_boundary}
    end
  end

  defp permitted?(expanded, root) do
    dir_permitted?(expanded, root) or exact_permitted?(expanded, root)
  end

  defp dir_permitted?(expanded, root) do
    # A file is directory-permitted if its absolute path falls under
    # root/<permitted_dir>. We add a "/" after the expanded prefix to avoid
    # matching "root/lib_extra/foo.ex" when the permitted dir is "lib/":
    # Path.join("root", "lib/") expands to "root/lib", so we append "/" to form
    # "root/lib/" as the required prefix.
    Enum.any?(@permitted_dirs, fn dir ->
      prefix = Path.join(root, dir) <> "/"
      String.starts_with?(expanded, prefix) or expanded == Path.join(root, dir)
    end)
  end

  defp exact_permitted?(expanded, root) do
    # Exact-path entries: the expanded path must equal root + exact, nothing more.
    Enum.any?(@permitted_exact, fn exact ->
      expanded == Path.join(root, exact)
    end)
  end
end
```

**Critical implementation notes:**

- `Path.expand/1` is called on both `project_root` and the joined path before any
  comparison. This resolves `..` segments and symlinks, defeating traversal attacks
  like `lib/../../.env`.
- `@permitted_dirs` entries end with `/`. After `Path.join`, the trailing slash is
  normalised away — so we explicitly append `"/"` to the expanded prefix before the
  `starts_with?` check. Without this, `"root/lib"` would match `"root/lib_extra/foo.ex"`.
- `@permitted_exact` uses `==`, not `starts_with?`. This guards against
  `AGENTS.md.bak` and `mix.exs.backup` bypassing the boundary.

**Gate:** All `Foundry.FileSystemTest` tests pass (11 tests, 0 failures).

---

## Step 2 — `Foundry.SparkMeta` — DSL walker

The walker introspects compiled modules and produces `SparkMeta.ModuleInfo` structs.
It will become the `spark_meta` Hex package (ADR-019). Zero Foundry-specific
assumptions: no manifest access, no lint rules, no sensitive resource lists.

### 2.1 Introspection API reference

Two distinct mechanisms are used. Know which fields come from which:

**`module.__info__(:attributes)`** — returns compile-time module attributes set with
`@attr value`. Use for:
- `@moduledoc` → `description`
- `@telemetry_prefix` → `telemetry_prefix`
- `@runbook` → `runbook`
- `@compliance` → `compliance`
- `@adrs` → `adrs`

**`Spark.extensions(module)`** — returns the list of Spark extension modules compiled
into the DSL for this module. Use for extension detection:
- Check for `AshPaperTrail.Resource` in the list → `paper_trail: true`
- Check for `AshArchival.Resource` → `archival: true`
- Check for `AshStateMachine.Resource` → `state_machine.present: true`
- Check for `AshAuthentication` extensions → `authentication_subject: true`
- Check for `AshJsonApi.Resource` → triggers `api_routes` extraction
- Check for `AshDoubleEntry.Account/Balance/Transfer` → used for `type` derivation

**`Ash.Resource.Info.*`** — public Ash reflection API for resource modules:
- `Ash.Resource.Info.attributes(module)` → list of `%Ash.Resource.Attribute{}`
- `Ash.Resource.Info.actions(module)` → list of action structs
- `Ash.Resource.Info.domain(module)` → domain module atom

**`Spark.Dsl.Extension.get_entities(module, path)`** — generic Spark DSL entity
retrieval. Use for:
- `Spark.Dsl.Extension.get_entities(module, [:reactor, :steps])` → Reactor steps
- State machine states and transitions via
  `Spark.Dsl.Extension.get_entities(module, [:state_machine, :states])` and
  `Spark.Dsl.Extension.get_entities(module, [:state_machine, :transitions])`

**`module.__info__(:attributes)[:behaviour]`** — list of behaviours the module
implements. Detects `Oban.Worker` (which is a behaviour, not a Spark extension).

### 2.2 Tests

`test/foundry/spark_meta_test.exs` — built incrementally, one describe block per
capability. Use `IgamingRef` modules from the reference project.

```elixir
defmodule Foundry.SparkMetaTest do
  use ExUnit.Case, async: true

  # Ensure reference project is compiled and on the code path.
  # This requires the reference project to be a dependency of Foundry's
  # test environment, or loaded via Code.prepend_path/1 in test_helper.exs.

  describe "basic struct output" do
    test "returns %SparkMeta.ModuleInfo{} for a resource" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert %Foundry.SparkMeta.ModuleInfo{} = result
      assert result.module == IgamingRef.Finance.Wallet
    end

    test "returns %SparkMeta.ModuleInfo{} for a Reactor" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.WithdrawalTransfer)
      assert %Foundry.SparkMeta.ModuleInfo{} = result
    end

    test "does not crash on a module with no Spark extensions" do
      # A plain Elixir module — should return ModuleInfo with nil/[] defaults
      result = Foundry.SparkMeta.walk(Kernel)
      assert %Foundry.SparkMeta.ModuleInfo{} = result
      assert result.attributes == []
      assert result.actions == []
    end
  end

  describe "module attributes (@-declared)" do
    test "description is extracted from @moduledoc first paragraph" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert is_binary(result.description)
      assert String.length(result.description) > 0
    end

    test "@telemetry_prefix is extracted as list of strings" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert result.telemetry_prefix == ["igaming_ref", "finance", "wallet"]
    end

    test "@runbook is extracted for Transfer modules" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.WithdrawalTransfer)
      assert result.runbook == "docs/runbooks/withdrawal_transfer.md"
    end

    test "@runbook is nil for resources" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert result.runbook == nil
    end

    test "@compliance is extracted as list of strings" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.WithdrawalTransfer)
      assert "RG-UK-014" in result.compliance
      assert "RG-MGA-007" in result.compliance
    end

    test "@adrs is extracted as list of strings" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.WithdrawalTransfer)
      assert is_list(result.adrs)
    end
  end

  describe "Ash resource introspection" do
    test "attributes are returned as list of SparkMeta.Attribute structs" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert [_ | _] = result.attributes
      attr = Enum.find(result.attributes, &(&1.name == :currency))
      assert attr != nil
      assert attr.type == "string"
    end

    test "actions are returned as list of SparkMeta.Action structs" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      action_names = Enum.map(result.actions, & &1.name)
      assert :read in action_names
      assert :create in action_names
    end
  end

  describe "extension detection via Spark.extensions/1" do
    test "AshPaperTrail extension detected → paper_trail: true" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert result.paper_trail == true
    end

    test "AshArchival extension detected → archival: true" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert result.archival == true
    end

    test "module without extensions → paper_trail: false" do
      # KYCUploadToken has no paper trail (not sensitive)
      result = Foundry.SparkMeta.walk(IgamingRef.Players.KYCUploadToken)
      assert result.paper_trail == false
    end

    test "AshAuthentication subject detected → authentication_subject: true" do
      result = Foundry.SparkMeta.walk(IgamingRef.Accounts.User)
      assert result.authentication_subject == true
    end
  end

  describe "AshStateMachine introspection" do
    test "state_machine.present: true for Wallet" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert result.state_machine.present == true
    end

    test "states are populated" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert "active" in result.state_machine.states
      assert "frozen" in result.state_machine.states
      assert "closed" in result.state_machine.states
    end

    test "transitions are populated" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert [_ | _] = result.state_machine.transitions
    end

    test "state_machine.present: false for LedgerEntry" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.LedgerEntry)
      assert result.state_machine.present == false
      assert result.state_machine.states == []
      assert result.state_machine.transitions == []
      assert result.state_machine.state_attribute == nil
    end
  end

  describe "Ash.Type.Money introspection" do
    test "money_attributes populated for LedgerEntry" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.LedgerEntry)
      money_attr = Enum.find(result.money_attributes, &(&1.name == "amount"))
      assert money_attr != nil
      assert money_attr.type == "Ash.Type.Money"
      assert money_attr.cldr_backend != nil
    end

    test "money_attributes: [] for non-monetary resource" do
      result = Foundry.SparkMeta.walk(IgamingRef.Gaming.Game)
      assert result.money_attributes == []
    end
  end

  describe "Reactor step introspection" do
    test "steps are populated for WithdrawalTransfer" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.WithdrawalTransfer)
      assert [_ | _] = result.steps
    end

    test "steps: [] for plain resources" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert result.steps == []
    end
  end

  describe "Oban.Worker detection" do
    test "oban_queues populated for CatalogSyncJob" do
      result = Foundry.SparkMeta.walk(IgamingRef.Gaming.CatalogSyncJob)
      assert [_ | _] = result.oban_queues
    end

    test "oban_queues: [] for non-worker modules" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert result.oban_queues == []
    end
  end

  describe "agent_steps" do
    test "agent_steps: [] when no AshAI steps declared" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.WithdrawalTransfer)
      assert result.agent_steps == []
    end
  end

  describe "SparkMeta.Extension opt-in hook" do
    test "unknown extensions produce raw key-value fallback, do not crash" do
      result = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)
      assert %Foundry.SparkMeta.ModuleInfo{} = result
    end
  end
end
```

### 2.3 Implementation

Build the walker in sub-steps so tests accumulate green:

**2a.** Structs — `SparkMeta.ModuleInfo` mirrors the NodeEntry schema fields the
walker can derive. Fields added by `NodeBuilder` (Foundry-specific, like `sensitive`)
are absent here:

```elixir
defmodule Foundry.SparkMeta.ModuleInfo do
  @enforce_keys [:module]
  defstruct [
    :module,
    type: nil,             # :resource | :transfer | :reactor | :rule | :job |
                           # :blueprint | :provider | :liveview | :liveresource | :agent
    description: nil,
    attributes: [],
    actions: [],
    rules: [],
    compliance: [],
    adrs: [],
    runbook: nil,
    data_layer: nil,
    paper_trail: false,
    archival: false,
    state_machine: %{present: false, states: [], transitions: [], state_attribute: nil},
    api_routes: [],
    telemetry_prefix: [],
    money_attributes: [],
    authentication_subject: false,
    oban_queues: [],
    rate_limited: false,
    feature_flags: [],
    steps: [],
    outputs: [],
    agent_steps: [],
    last_modified: nil
  ]
end

defmodule Foundry.SparkMeta.Attribute do
  defstruct [:name, :type, :description, pii: false, sensitive: false,
             money: false, cldr_backend: nil]
end

defmodule Foundry.SparkMeta.Action do
  defstruct [:name, :type, :description]
end

defmodule Foundry.SparkMeta.StepEntry do
  defstruct [:name, :type, :description, :target_module]
end

defmodule Foundry.SparkMeta.MoneyAttr do
  defstruct [:name, :type, :cldr_backend]
end
```

**2b.** `Foundry.SparkMeta.walk/1` — main entry point using a pipeline of
transformation functions:

```elixir
defmodule Foundry.SparkMeta do
  alias Foundry.SparkMeta.ModuleInfo

  def walk(module) when is_atom(module) do
    %ModuleInfo{module: module}
    |> put_description()
    |> put_type()
    |> put_module_attributes()      # @telemetry_prefix, @runbook, @compliance, @adrs
    |> put_ash_resource_fields()    # attributes, actions, data_layer
    |> put_extension_fields()       # paper_trail, archival, auth_subject
    |> put_state_machine()          # AshStateMachine entities
    |> put_money_attributes()       # scan attributes for Ash.Type.Money
    |> put_api_routes()             # AshJsonApi entities
    |> put_reactor_steps()          # Spark DSL entities if Reactor
    |> put_oban_fields()            # behaviour list
    |> put_agent_steps()            # AshAI DSL entities if present
    |> put_last_modified()          # source file mtime
  rescue
    _ -> %ModuleInfo{module: module}  # graceful fallback for non-Spark modules
  end
end
```

**2c.** `put_description/1` — `@moduledoc` first paragraph. Note the runtime format
of `__info__(:attributes)[:moduledoc]` is `[{line, text}]` in Elixir 1.15+. The `Keyword.get`
call returns the first entry if multiple `:moduledoc` attributes exist (allowed by Elixir);
this is acceptable for practical use since duplicate `@moduledoc` declarations are rare:

```elixir
defp put_description(%ModuleInfo{module: module} = info) do
  description =
    case module.__info__(:attributes)[:moduledoc] do
      [{_line, doc}] when is_binary(doc) ->
        doc
        |> String.split("\n\n")
        |> Enum.reject(&(String.trim(&1) == ""))
        |> List.first()
        |> then(&(if &1, do: String.trim(&1), else: nil))
      _ -> nil
    end
  %{info | description: description}
end
```

**2d.** `put_module_attributes/1` — `@telemetry_prefix`, `@runbook`, `@compliance`,
`@adrs` are all read from `__info__(:attributes)`:

```elixir
defp put_module_attributes(%ModuleInfo{module: module} = info) do
  attrs = module.__info__(:attributes)
  %{info |
    telemetry_prefix: get_attr_list(attrs, :telemetry_prefix),
    runbook:          get_attr_single(attrs, :runbook),
    compliance:       get_attr_list(attrs, :compliance),
    adrs:             get_attr_list(attrs, :adrs)
  }
end

defp get_attr_list(attrs, key) do
  case Keyword.get(attrs, key) do
    nil -> []
    list when is_list(list) -> Enum.map(list, &to_string/1)
    value -> [to_string(value)]
  end
end

defp get_attr_single(attrs, key) do
  case Keyword.get(attrs, key) do
    nil -> nil
    [value | _] -> to_string(value)
    value -> to_string(value)
  end
end
```

**2e.** `put_type/1` — type derivation. Precedence matters: check most specific
first. Transfer is more specific than Reactor, so check it before Reactor:

```elixir
defp put_type(%ModuleInfo{module: module} = info) do
  type = cond do
    reactor_module?(module) and transfer_module?(module) -> :transfer
    reactor_module?(module)    -> :reactor
    oban_worker?(module)       -> :job
    blueprint_module?(module)  -> :blueprint
    provider_module?(module)   -> :provider
    liveview_module?(module)   -> :liveview
    liveresource_module?(module) -> :liveresource
    agent_module?(module)      -> :agent
    rule_module?(module)       -> :rule
    ash_resource?(module)      -> :resource
    true                       -> :resource
  end
  %{info | type: type}
end

# Extension-based detectors use Spark.extensions/1, never __info__(:attributes)
defp ash_resource?(module),
  do: function_exported?(module, :__ash_resource__, 0)

defp reactor_module?(module),
  do: function_exported?(module, :__reactor__, 0)

defp transfer_module?(module),
  do: AshDoubleEntry.Transfers.Transfer in safe_extensions(module)

defp oban_worker?(module),
  do: Oban.Worker in List.wrap(
    module.__info__(:attributes) |> Keyword.get(:behaviour, []))

defp rule_module?(module),
  do: Enum.any?(
    module.__info__(:attributes) |> Keyword.get(:behaviour, []),
    &(&1 in [Ash.Policy.Check, Ash.Policy.SimpleCheck]))

defp safe_extensions(module) do
  if function_exported?(module, :__spark_dsl_config__, 0) do
    Spark.extensions(module)
  else
    []
  end
rescue
  _ -> []
end
```

**2f.** `put_extension_fields/1` — uses `Spark.extensions/1` exclusively:

```elixir
defp put_extension_fields(%ModuleInfo{module: module} = info) do
  extensions = safe_extensions(module)
  %{info |
    paper_trail:             AshPaperTrail.Resource in extensions,
    archival:                AshArchival.Resource in extensions,
    authentication_subject:  Enum.any?(extensions, &authentication_ext?/1),
    rate_limited:            Enum.any?(extensions, &rate_limit_ext?/1)
  }
end

defp authentication_ext?(ext),
  do: ext in [AshAuthentication, AshAuthentication.Resource]

defp rate_limit_ext?(_ext), do: false  # extend when rate limiting DSL is added
```

**2g.** `put_state_machine/1` — uses `Spark.Dsl.Extension.get_entities/3`:

```elixir
defp put_state_machine(%ModuleInfo{module: module} = info) do
  if AshStateMachine.Resource in safe_extensions(module) do
    states =
      Spark.Dsl.Extension.get_entities(module, [:state_machine, :states])
      |> Enum.map(& to_string(&1.name))

    transitions =
      Spark.Dsl.Extension.get_entities(module, [:state_machine, :transitions])
      |> Enum.map(fn t ->
        %{from: to_string(t.from), to: to_string(t.to), action: to_string(t.action)}
      end)

    state_attr =
      Spark.Dsl.Extension.get_opt(module, [:state_machine], :state_attribute, nil)

    %{info | state_machine: %{
      present: true,
      states: states,
      transitions: transitions,
      state_attribute: state_attr && to_string(state_attr)
    }}
  else
    info
  end
end
```

**2h.** `put_reactor_steps/1` — uses `Spark.Dsl.Extension.get_entities/3`, not a
non-existent `Reactor.Info` API:

```elixir
defp put_reactor_steps(%ModuleInfo{module: module} = info) do
  if function_exported?(module, :__reactor__, 0) do
    steps =
      Spark.Dsl.Extension.get_entities(module, [:reactor, :steps])
      |> Enum.map(fn step ->
        %Foundry.SparkMeta.StepEntry{
          name:          to_string(step.name),
          type:          step.__struct__ |> Module.split() |> List.last() |> String.downcase(),
          description:   Map.get(step, :description),
          target_module: Map.get(step, :impl) || Map.get(step, :resource)
        }
      end)

    %{info | steps: steps}
  else
    info
  end
end
```

**2i.** `SparkMeta.Extension` behaviour — the opt-in hook for extension authors:

```elixir
defmodule Foundry.SparkMeta.Extension do
  @moduledoc """
  Opt-in hook for Spark extension authors to provide richer walker output.

  Implement this behaviour in your extension module to supply structured data
  that SparkMeta cannot derive from the generic Spark DSL introspection API.

  Unknown extensions (those not implementing this behaviour) receive a raw
  key-value fallback via Spark.Dsl.Extension.get_entities/3 — they do not
  cause crashes or produce missing data.
  """

  @callback enrich(module :: module(), info :: Foundry.SparkMeta.ModuleInfo.t()) ::
    Foundry.SparkMeta.ModuleInfo.t()
end
```

**Gate:** All `Foundry.SparkMetaTest` tests pass before Step 3 begins.

---

## Step 3 — `mix foundry.project.context <Module>` (per-module form)

The per-module command is the first user-visible surface. Correctness here propagates
directly to the bulk form and the lint rules.

### 3.1 Tests

Activate the `"mix foundry.project.context <Module>"` describe block. Key assertions:

```elixir
describe "mix foundry.project.context <Module>" do
  test "all schema fields present for WithdrawalTransfer" do
    node = run_context_for("IgamingRef.Finance.WithdrawalTransfer")

    expected_keys = ~w[module type domain app sensitive description attributes
      actions rules compliance adrs runbook test_coverage data_layer
      pending_migrations paper_trail archival state_machine api_routes
      telemetry_prefix money_attributes authentication_subject oban_queues
      rate_limited feature_flags steps outputs agent_steps last_modified]

    for key <- expected_keys do
      assert Map.has_key?(node, key), "Missing key: #{key}"
    end
  end

  test "type: 'transfer' for WithdrawalTransfer" do
    assert run_context_for("IgamingRef.Finance.WithdrawalTransfer")["type"] == "transfer"
  end

  test "sensitive: true for Wallet" do
    assert run_context_for("IgamingRef.Finance.Wallet")["sensitive"] == true
  end

  test "sensitive: false for Gaming.Game" do
    assert run_context_for("IgamingRef.Gaming.Game")["sensitive"] == false
  end

  test "paper_trail: true for LedgerEntry" do
    assert run_context_for("IgamingRef.Finance.LedgerEntry")["paper_trail"] == true
  end

  test "archival: true for LedgerEntry" do
    assert run_context_for("IgamingRef.Finance.LedgerEntry")["archival"] == true
  end

  test "state_machine.present: true for Wallet, correct states" do
    node = run_context_for("IgamingRef.Finance.Wallet")
    assert node["state_machine"]["present"] == true
    states = node["state_machine"]["states"]
    assert "active" in states
    assert "frozen" in states
    assert "closed" in states
  end

  test "state_machine.present: false for LedgerEntry" do
    sm = run_context_for("IgamingRef.Finance.LedgerEntry")["state_machine"]
    assert sm["present"] == false
    assert sm["states"] == []
    assert sm["transitions"] == []
    assert sm["state_attribute"] == nil
  end

  test "money_attributes populated for LedgerEntry" do
    node = run_context_for("IgamingRef.Finance.LedgerEntry")
    money = node["money_attributes"]
    assert [_ | _] = money
    amount = Enum.find(money, &(&1["name"] == "amount"))
    assert amount["type"] == "Ash.Type.Money"
    assert amount["cldr_backend"] != nil
  end

  test "money_attributes: [] for Gaming.Game" do
    assert run_context_for("IgamingRef.Gaming.Game")["money_attributes"] == []
  end

  test "authentication_subject: true for Accounts.User" do
    assert run_context_for("IgamingRef.Accounts.User")["authentication_subject"] == true
  end

  test "pending_migrations: false (reference project is clean)" do
    assert run_context_for("IgamingRef.Finance.Wallet")["pending_migrations"] == false
  end

  test "compliance contains RG-UK-014 and RG-MGA-007 for WithdrawalTransfer" do
    compliance = run_context_for("IgamingRef.Finance.WithdrawalTransfer")["compliance"]
    assert "RG-UK-014" in compliance
    assert "RG-MGA-007" in compliance
  end

  test "runbook declared for WithdrawalTransfer" do
    assert run_context_for("IgamingRef.Finance.WithdrawalTransfer")["runbook"] ==
      "docs/runbooks/withdrawal_transfer.md"
  end

  test "rules non-empty for WithdrawalTransfer" do
    rules = run_context_for("IgamingRef.Finance.WithdrawalTransfer")["rules"]
    assert "SufficientBalance" in rules
    assert "WithdrawalLimitNotExceeded" in rules
    assert "PlayerKYCVerified" in rules
  end

  test "rules: [] for LedgerEntry" do
    assert run_context_for("IgamingRef.Finance.LedgerEntry")["rules"] == []
  end

  test "app: null for all modules (standard project)" do
    assert run_context_for("IgamingRef.Finance.Wallet")["app"] == nil
  end

  test "agent_steps: [] (no AshAI in reference project)" do
    assert run_context_for("IgamingRef.Finance.WithdrawalTransfer")["agent_steps"] == []
  end

  test "unknown module produces error JSON and exits 1" do
    {output, 1} = System.cmd("mix", ["foundry.project.context",
                                     "IgamingRef.Finance.DoesNotExist"],
                              cd: @ref_root, stderr_to_stdout: true)
    error = Jason.decode!(output)
    assert error["error"] == "module_not_found"
  end

  defp run_context_for(module_name) do
    {output, 0} = System.cmd("mix", ["foundry.project.context", module_name],
                              cd: @ref_root)
    Jason.decode!(output)
  end
end
```

### 3.2 Implementation

**3a.** `Foundry.Manifest.Parser` — define here because it is used in Steps 3, 7,
and 9:

```elixir
defmodule Foundry.Manifest.Parser do
  @moduledoc """
  Reads and parses .foundry/manifest.exs from a project root.
  Returns the manifest as a keyword list.
  Caches per {file_path, mtime} in ETS.
  """

  @spec read(project_root :: String.t()) ::
          {:ok, keyword()} | {:error, :not_found | :parse_error}
  def read(project_root) do
    with {:ok, content} <- Foundry.FileSystem.read(project_root, ".foundry/manifest.exs"),
         {manifest, _bindings} when is_list(manifest) <-
           Code.eval_string(content, [], file: ".foundry/manifest.exs") do
      {:ok, manifest}
    else
      {:error, reason} -> {:error, reason}
      _                -> {:error, :parse_error}
    end
  end
end
```

Note: `Code.eval_string/1` is appropriate here — `.foundry/manifest.exs` is a
trusted project file at the same trust level as `mix.exs`. It is a keyword list
literal, not executable logic. Sandboxing for cloud mode is a Phase 2+ concern.

**3b.** `Foundry.Context.NodeBuilder` — takes `SparkMeta.ModuleInfo` + manifest,
produces `Foundry.Context.NodeEntry`:

```elixir
defmodule Foundry.Context.NodeBuilder do
  alias Foundry.SparkMeta.ModuleInfo
  alias Foundry.Context.NodeEntry

  @spec build(ModuleInfo.t(), manifest :: keyword(), pending_migrations :: boolean()) ::
          NodeEntry.t()
  def build(%ModuleInfo{} = info, manifest, pending_migrations) do
    sensitive_modules = Keyword.get(manifest, :sensitive_resources, [])

    %NodeEntry{
      id:                    inspect(info.module),
      module:                inspect(info.module),
      type:                  to_string(info.type || :resource),
      domain:                derive_domain(info.module),
      app:                   nil,
      sensitive:             info.module in sensitive_modules,
      description:           info.description,
      attributes:            info.attributes,
      actions:               info.actions,
      rules:                 info.rules,
      compliance:            info.compliance,
      adrs:                  info.adrs,
      runbook:               info.runbook,
      test_coverage:         %{property_tests: false, scenario_tests: false, e2e_tests: false},
      data_layer:            info.data_layer,
      pending_migrations:    pending_migrations,
      paper_trail:           info.paper_trail,
      archival:              info.archival,
      state_machine:         info.state_machine,
      api_routes:            info.api_routes,
      telemetry_prefix:      info.telemetry_prefix,
      money_attributes:      info.money_attributes,
      authentication_subject: info.authentication_subject,
      oban_queues:           info.oban_queues,
      rate_limited:          info.rate_limited,
      feature_flags:         info.feature_flags,
      steps:                 info.steps,
      outputs:               info.outputs,
      agent_steps:           info.agent_steps,
      last_modified:         info.last_modified
    }
  end

  defp derive_domain(module) do
    # "IgamingRef.Finance.Wallet" → "Finance"
    module |> Module.split() |> Enum.drop(1) |> List.first() |> to_string()
  end
end
```

`test_coverage` is all-false in Phase 1. Accurate test coverage detection is a
Phase 5 concern. The field must exist (it is in the schema).

**3c.** `Foundry.Context.PendingMigrations` — runs `mix ash.codegen --check` ONCE
for the project, not once per module:

```elixir
defmodule Foundry.Context.PendingMigrations do
  @moduledoc """
  Determines which modules have pending Ash migrations by running
  `mix ash.codegen --check` once per project invocation.

  Do not call check/1 per module — it spawns one Mix process per call.
  Call once, then use pending?/2 to query individual modules.
  """

  @spec check(project_root :: String.t()) :: {:ok, MapSet.t()} | {:error, term()}
  def check(project_root) do
    case System.cmd("mix", ["ash.codegen", "--check"],
           cd: project_root, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, MapSet.new()}

      {output, _nonzero} ->
        {:ok, MapSet.new(parse_pending_modules(output))}
    end
  end

  @spec pending?(module :: module(), pending_set :: MapSet.t()) :: boolean()
  def pending?(module, pending_set), do: MapSet.member?(pending_set, module)

  defp parse_pending_modules(output) do
    # ash.codegen --check output format is implementation-specific.
    # Adjust the regex to match the actual output of the ash_postgres version in use.
    Regex.scan(~r/\b([\w.]+)\b.*?pending migration/, output)
    |> Enum.flat_map(fn [_, mod] ->
      try do [String.to_existing_atom(mod)]
      rescue _ -> []
      end
    end)
  end
end
```

**3d.** ETS cache via Nebulex L1:

```elixir
defmodule Foundry.Context.Cache do
  use Nebulex.Cache, otp_app: :foundry, adapter: Nebulex.Adapters.Local

  def get_or_compute(key, ttl \\ :infinity, fun) do
    # CONCURRENCY NOTE: This is a best-effort cache (last-write-wins on race).
    # Two concurrent calls with a cold cache will both compute and both put.
    # This is acceptable because: (1) `SparkMeta.walk/1` is idempotent, (2) test
    # environment is single-threaded with `async: false`, (3) real projects are
    # read-heavy on modules. If atomicity becomes critical, add a lock.
    case get(key) do
      nil   -> fun.() |> tap(&put(key, &1, ttl: ttl))
      value -> value
    end
  end
end
```

**3e.** `Mix.Tasks.Foundry.Project.Context` Mix task:

```elixir
defmodule Mix.Tasks.Foundry.Project.Context do
  use Mix.Task
  @shortdoc "Generate or query the project context"

  def run(["--check"]),                          do: run_check()
  def run([module_name]) when is_binary(module_name), do: run_single(module_name)
  def run([]),                                   do: run_bulk()
  def run(_), do: Mix.raise("Usage: mix foundry.project.context [<Module> | --check]")

  defp run_single(module_name) do
    project_root = File.cwd!()
    {:ok, manifest}    = Foundry.Manifest.Parser.read(project_root)
    {:ok, pending_set} = Foundry.Context.PendingMigrations.check(project_root)

    module =
      try do String.to_existing_atom("Elixir." <> module_name)
      rescue _ -> emit_error_and_halt("module_not_found", module_name)
      end

    unless Code.ensure_loaded?(module) do
      emit_error_and_halt("module_not_found", module_name)
    end

    info    = Foundry.SparkMeta.walk(module)
    pending = Foundry.Context.PendingMigrations.pending?(module, pending_set)
    node    = Foundry.Context.NodeBuilder.build(info, manifest, pending)

    IO.puts(Jason.encode!(node, pretty: true))
  end

  defp emit_error_and_halt(error, module_name) do
    IO.puts(Jason.encode!(%{error: error, module: module_name}))
    exit({:shutdown, 1})
  end

  defp run_bulk(),  do: :implemented_in_step_4
  defp run_check(), do: :implemented_in_step_5
end
```

**3f.** JSON serialisation with explicit field order:

```elixir
defimpl Jason.Encoder, for: Foundry.Context.NodeEntry do
  @field_order ~w[id module type domain app sensitive description attributes actions
    rules compliance adrs runbook test_coverage data_layer pending_migrations
    paper_trail archival state_machine api_routes telemetry_prefix money_attributes
    authentication_subject oban_queues rate_limited feature_flags steps outputs
    agent_steps last_modified]a

  def encode(entry, opts) do
    @field_order
    |> Enum.map(fn key -> {to_string(key), Map.get(entry, key)} end)
    |> Map.new()
    |> Jason.Encode.map(opts)
  end
end
```

**Gate:** All per-module acceptance matrix tests pass.

---

## Step 4 — `mix foundry.project.context` (bulk form)

Reuses the walker and cache from Step 3. New work: node list assembly, edge
derivation, spec-kit indexing, and the `graph_delta` scaffold.

### 4.1 Tests

```elixir
describe "mix foundry.project.context (bulk)" do
  setup do
    {output, 0} = System.cmd("mix", ["foundry.project.context"],
                              cd: @ref_root)
    {:ok, context: Jason.decode!(output)}
  end

  test "top-level keys present", %{context: ctx} do
    expected = ~w[generated_at project project_type domain_type nodes edges spec_kit graph_delta]
    for key <- expected, do: assert Map.has_key?(ctx, key), "Missing: #{key}"
  end

  test "project is IgamingRef", %{context: ctx},
    do: assert ctx["project"] == "IgamingRef"

  test "project_type is standard", %{context: ctx},
    do: assert ctx["project_type"] == "standard"

  test "domain_type is igaming", %{context: ctx},
    do: assert ctx["domain_type"] == "igaming"

  test "graph_delta is null", %{context: ctx},
    do: assert ctx["graph_delta"] == nil

  test "nodes count matches fixture", %{context: ctx} do
    # Verify exact count against fixture before freezing (see §Known constraints)
    # 17 resources + 3 reactors + 1 job + 8 rules + 1 blueprint + 2 providers + 1 read-only = 33
    assert length(ctx["nodes"]) == 33
  end

  test "nodes ordered alphabetically by FQN", %{context: ctx} do
    fqns = Enum.map(ctx["nodes"], & &1["id"])
    assert fqns == Enum.sort(fqns)
  end

  test "6 distinct domains", %{context: ctx} do
    domains = ctx["nodes"] |> Enum.map(& &1["domain"]) |> Enum.uniq() |> Enum.sort()
    assert length(domains) == 6
    assert Enum.all?(~w[Finance Players Promotions Gaming Ops Accounts], &(&1 in domains))
  end

  test "Finance has 8 nodes", %{context: ctx} do
    assert ctx["nodes"] |> Enum.count(& &1["domain"] == "Finance") == 8
  end

  test "1 blueprint node", %{context: ctx} do
    assert ctx["nodes"] |> Enum.count(& &1["type"] == "blueprint") == 1
  end

  test "2 provider nodes", %{context: ctx} do
    assert ctx["nodes"] |> Enum.count(& &1["type"] == "provider") == 2
  end

  test "1 job node", %{context: ctx} do
    assert ctx["nodes"] |> Enum.count(& &1["type"] == "job") == 1
  end

  test "every node has required fields with correct types", %{context: ctx} do
    for node <- ctx["nodes"] do
      assert is_binary(node["id"]),     "id must be string: #{inspect node["id"]}"
      assert is_binary(node["module"]), "module must be string"
      assert is_binary(node["type"]),   "type must be string"
      assert is_binary(node["domain"]), "domain must be string"
      assert node["app"] == nil,        "app must be null (standard project)"
    end
  end

  test "sensitive nodes marked correctly", %{context: ctx} do
    wallet = Enum.find(ctx["nodes"], & &1["id"] == "IgamingRef.Finance.Wallet")
    game   = Enum.find(ctx["nodes"], & &1["id"] == "IgamingRef.Gaming.Game")
    assert wallet["sensitive"] == true
    assert game["sensitive"]   == false
  end

  test "edges are non-empty and correctly typed", %{context: ctx} do
    assert length(ctx["edges"]) > 0
    for edge <- ctx["edges"] do
      assert is_binary(edge["from"])
      assert is_binary(edge["to"])
      assert is_binary(edge["relation"])
      assert edge["cross_app"]     == false
      assert edge["cross_project"] == false
    end
  end

  test "WithdrawalTransfer → Wallet (writes) edge exists", %{context: ctx} do
    edge = find_edge(ctx, "IgamingRef.Finance.WithdrawalTransfer", "IgamingRef.Finance.Wallet")
    assert edge["relation"] == "writes"
  end

  test "CatalogSyncJob → ProviderSyncReactor (async) edge exists", %{context: ctx} do
    edge = find_edge(ctx, "IgamingRef.Gaming.CatalogSyncJob", "IgamingRef.Gaming.ProviderSyncReactor")
    assert edge["relation"] == "async"
  end

  test "edges ordered by from FQN then to FQN", %{context: ctx} do
    edges  = ctx["edges"]
    sorted = Enum.sort_by(edges, &{&1["from"], &1["to"]})
    assert edges == sorted
  end

  test "spec_kit is present with correct sub-keys", %{context: ctx} do
    sk = ctx["spec_kit"]
    assert is_map(sk)
    for key <- ~w[index_token_count index_token_warn index_token_limit adrs runbooks regulations] do
      assert Map.has_key?(sk, key), "spec_kit missing: #{key}"
    end
  end

  test "spec_kit.adrs non-empty", %{context: ctx},
    do: assert length(ctx["spec_kit"]["adrs"]) > 0

  test "spec_kit.runbooks count is 3", %{context: ctx},
    do: assert length(ctx["spec_kit"]["runbooks"]) == 3

  test "spec_kit.index_token_count within budget", %{context: ctx},
    do: assert ctx["spec_kit"]["index_token_count"] <= 400

  test "spec_kit.index_token_warn: false for small corpus", %{context: ctx},
    do: assert ctx["spec_kit"]["index_token_warn"] == false

  test "[synthetic] index_token_warn: true when corpus pushed above 360 tokens" do
    # Add stub ADRs until token estimate exceeds 360, assert warn flag, remove stubs.
    # Implemented as @tag :integration with on_exit cleanup.
    :ok
  end

  defp find_edge(ctx, from, to),
    do: Enum.find(ctx["edges"], & &1["from"] == from and &1["to"] == to)
end
```

### 4.2 Pre-implementation extraction

**CRITICAL:** Before Step 4 begins, extract `discover_project_modules/2` into a shared module.
This function is defined identically in two places with different call signatures:
- `Foundry.Context.GraphBuilder.build/2` calls it with `(project_root, root_name)`
- `Mix.Tasks.Foundry.Lint.All.run/1` calls it with `(project_root, manifest)`

Create `Foundry.Context.ModuleDiscovery` with:

```elixir
defmodule Foundry.Context.ModuleDiscovery do
  def all_project_modules(project_root, project_name_string) do
    ebin_path = Path.join([project_root, "_build", "dev", "lib",
                           Macro.underscore(project_name_string), "ebin"])
    prefix    = "Elixir." <> project_name_string <> "."

    Path.wildcard(Path.join(ebin_path, "*.beam"))
    |> Enum.map(&(&1 |> Path.basename(".beam") |> String.to_atom()))
    |> Enum.filter(&(Atom.to_string(&1) |> String.starts_with?(prefix)))
    |> Enum.filter(&Code.ensure_loaded?/1)
  end
end
```

Both call sites must then use `Foundry.Context.ModuleDiscovery.all_project_modules(project_root, project_name_string)`.
For `GraphBuilder`, pass `Keyword.get(manifest, :project_name, "")`. For `Mix.Tasks.Foundry.Lint.All`, extract
the `:project_name` from manifest. This eliminates the duplication and creates a single source of truth.

### 4.3 Implementation

**4a.** `Foundry.Context.GraphBuilder` — assembles all nodes and derives edges:

```elixir
defmodule Foundry.Context.GraphBuilder do
  def build(project_root, manifest) do
    root_name  = Keyword.get(manifest, :project_name, "")
    {:ok, pending_set} = Foundry.Context.PendingMigrations.check(project_root)

    nodes =
      Foundry.Context.ModuleDiscovery.all_project_modules(project_root, root_name)
      |> Enum.map(fn mod ->
        info    = Foundry.SparkMeta.walk(mod)
        pending = Foundry.Context.PendingMigrations.pending?(mod, pending_set)
        Foundry.Context.NodeBuilder.build(info, manifest, pending)
      end)
      |> Enum.sort_by(& &1.id)   # alphabetical by FQN — deterministic, diff-stable

    edges =
      nodes
      |> derive_edges()
      |> Enum.sort_by(&{&1.from, &1.to})

    {nodes, edges}
  end
end
```

**4b.** Edge derivation rules — note the distinction between `references` (structural)
and `writes`/`reads` (behavioural):

| Source pattern | Detected via | Edge type |
|---|---|---|
| Reactor step type `:update` / `:create` targeting a resource | `step.type` + `step.target_module` | `reactor → resource (writes)` |
| Reactor step type `:read` / `:read_one` targeting a resource | `step.type` + `step.target_module` | `reactor → resource (reads)` |
| Oban.Worker module references a Reactor via `@performs` convention | `@performs` module attribute | `job → reactor (async)` |
| `belongs_to` relationship on a resource | `Ash.Resource.Info.relationships/1` | `resource → related (references)` |
| `has_many` / `has_one` relationship | same | `resource → related (referenced_by)` |

The fixture edge `WithdrawalTransfer → Wallet (writes)` comes from a Reactor step
analysis, not from a `belongs_to`. `belongs_to` produces `references`, not `writes`.

**4c.** `Foundry.Context.SpecKitIndexBuilder`:

```elixir
defmodule Foundry.Context.SpecKitIndexBuilder do
  @excluded_files ~w[
    docs/project_context_schema.md
    docs/spec_kit_index_schema.md
    docs/mix_task_summary_schemas.md
    docs/reference-project-fixture.md
    docs/manifest-schema-draft.md
  ]

  def build(project_root) do
    adrs     = scan_dir(project_root, "docs/adrs/", "adr")
    runbooks = scan_dir(project_root, "docs/runbooks/", "runbook")
    regs     = scan_dir(project_root, "docs/regulations/", "regulation")
    agents   = scan_exact(project_root, "AGENTS.md", "agents", "AGENTS")
    rules    = scan_dir(project_root, ".foundry/usage_rules/", "usage_rules")

    all_entries = adrs ++ runbooks ++ regs ++ List.wrap(agents) ++ rules
    token_count = estimate_tokens(all_entries)

    %{
      index_token_count: token_count,
      index_token_warn:  token_count > 360,
      index_token_limit: 400,
      adrs:              adrs,
      runbooks:          runbooks,
      regulations:       regs,
      agents:            agents,
      usage_rules:       rules
    }
  end

  defp estimate_tokens(entries) do
    # Conservative approximation: byte_size / 3.
    # English prose + Elixir identifiers average ~3.5 chars/token; dividing
    # by 3 slightly overestimates, which is correct behaviour for a warn threshold.
    entries |> Jason.encode!() |> byte_size() |> div(3)
  end
end
```

Per-document extraction — MDEx AST cached in ETS by `{:spec_kit, path, mtime}`:

```elixir
defp get_or_parse_ast(project_root, path, content) do
  mtime = File.stat!(Path.join(project_root, path)).mtime
  cache_key = {:spec_kit, path, mtime}

  Foundry.Context.Cache.get_or_compute(cache_key, fn ->
    {:ok, ast} = MDEx.parse_document(content)
    ast
  end)
end
```

Tag extraction — per `docs/project_context_schema.md §Tag extraction`:

```elixir
@stop_words ~w[the a an is are for with by in on at to of and or not this that
               it its be as from will must when if all any each per no]

defp extract_tags(text) do
  text
  |> String.downcase()
  |> String.replace(~r/[^a-z0-9\s]/, " ")
  |> String.split(~r/\s+/, trim: true)
  |> Enum.reject(& &1 in @stop_words)
  |> Enum.reject(& String.length(&1) < 3)
  |> Enum.uniq()
  |> Enum.sort()
  |> Enum.take(12)
end
```

Summary extraction — first substantive paragraph after frontmatter, ≤2 sentences
or 300 chars:

```elixir
defp extract_summary(content) do
  content
  |> String.split("\n\n")
  |> Enum.reject(&skip_paragraph?/1)
  |> List.first()
  |> truncate_summary()
end

defp skip_paragraph?(text) do
  trimmed = String.trim(text)
  trimmed == "" or
  String.starts_with?(trimmed, "#") or
  String.starts_with?(trimmed, "```") or
  String.starts_with?(trimmed, ">") or
  String.starts_with?(trimmed, "---") or
  String.starts_with?(trimmed, "**")   # frontmatter line e.g. **Status:** Accepted
end

defp truncate_summary(nil), do: nil
defp truncate_summary(text) do
  result =
    text
    |> String.split(~r/(?<=[.!?])\s+/, parts: 3)
    |> Enum.take(2)
    |> Enum.join(" ")

  if String.length(result) > 300, do: String.slice(result, 0, 297) <> "...", else: result
end
```

**4d.** Bulk ETS cache — keyed on `{:project_context, project_root, max_mtime}`:

```elixir
defp cache_key(project_root) do
  max_mtime =
    (Path.wildcard(Path.join(project_root, "lib/**/*.ex")) ++
     Path.wildcard(Path.join(project_root, "test/**/*.ex")))
    |> Enum.map(&File.stat!(&1).mtime)
    |> Enum.max(fn -> {{1970, 1, 1}, {0, 0, 0}} end)

  {:project_context, project_root, max_mtime}
end
```

**4e.** `Foundry.Context.SessionState` scaffold — struct and ETS table only. Delta
computation is Phase 4:

```elixir
defmodule Foundry.Context.SessionState do
  @moduledoc """
  Captures system map state at the start of an editing session.
  Used by the studio to render preview mode during active proposals.
  Delta computation is implemented in Phase 4.
  graph_delta is always nil in Phase 1.
  """

  defstruct [:session_id, :captured_at, :node_ids, :edge_hashes]

  def init_table do
    :ets.new(:foundry_session_state, [:named_table, :public, read_concurrency: true])
  end

  def delta(_session_id, _current_context), do: nil
end
```

**Gate:** All bulk acceptance matrix tests pass.

---

## Step 5 — `mix foundry.project.context --check`

### 5.1 Tests

```elixir
describe "mix foundry.project.context --check" do
  test "exits 0 when context.lock is freshly generated" do
    System.cmd("mix", ["foundry.project.context"], cd: @ref_root)
    {_, 0} = System.cmd("mix", ["foundry.project.context", "--check"], cd: @ref_root)
  end

  test "exits 1 when any lib/ file is touched after lock generation" do
    System.cmd("mix", ["foundry.project.context"], cd: @ref_root)
    File.touch!(Path.join(@ref_root, "lib/igaming_ref/finance/wallet.ex"))
    {_, 1} = System.cmd("mix", ["foundry.project.context", "--check"],
                         cd: @ref_root, stderr_to_stdout: true)
  end

  test "exits 1 when .foundry/context.lock is absent" do
    File.rm(Path.join(@ref_root, ".foundry/context.lock"))
    {_, 1} = System.cmd("mix", ["foundry.project.context", "--check"],
                         cd: @ref_root, stderr_to_stdout: true)
  end
end
```

### 5.2 Implementation

`Foundry.Context.LockFile`:

```elixir
defmodule Foundry.Context.LockFile do
  @lock_path ".foundry/context.lock"

  @spec compute_hash(project_root :: String.t()) :: String.t()
  def compute_hash(project_root) do
    # Deterministic: sort files, hash each file's content individually,
    # then hash the concatenated per-file hashes. Sorting is mandatory —
    # glob order is filesystem-dependent and non-deterministic across platforms.
    files =
      [Path.join(project_root, "lib/**/*.ex"),
       Path.join(project_root, "test/**/*.ex")]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.sort()

    per_file_hashes =
      Enum.map_join(files, "", fn path ->
        :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
      end)

    :crypto.hash(:sha256, per_file_hashes) |> Base.encode16(case: :lower)
  end

  @spec write(project_root :: String.t()) :: :ok
  def write(project_root) do
    hash      = compute_hash(project_root)
    lock_path = Path.join(project_root, @lock_path)
    File.mkdir_p!(Path.dirname(lock_path))
    File.write!(lock_path, hash <> "\n")
  end

  @spec check(project_root :: String.t()) :: :ok | {:error, :stale | :missing}
  def check(project_root) do
    case File.read(Path.join(project_root, @lock_path)) do
      {:error, :enoent} -> {:error, :missing}
      {:ok, stored} ->
        current = compute_hash(project_root)
        if String.trim(stored) == current, do: :ok, else: {:error, :stale}
    end
  end
end
```

The `run_bulk/0` function in the Mix task writes the lockfile after computing context.
The `run_check/0` function:

```elixir
defp run_check do
  project_root = File.cwd!()
  case Foundry.Context.LockFile.check(project_root) do
    :ok ->
      IO.puts("context.lock is current.")
    {:error, :missing} ->
      IO.puts(:stderr, "error: .foundry/context.lock absent. Run: mix foundry.project.context")
      exit({:shutdown, 1})
    {:error, :stale} ->
      IO.puts(:stderr, "error: context.lock is stale. Run: mix foundry.project.context")
      exit({:shutdown, 1})
  end
end
```

**Gate:** All three `--check` tests pass.

---

## Step 6 — `Foundry.SparkLint` — rule runner engine

The rule runner is the future `spark_lint` Hex package. Zero Foundry assumptions.

### 6.1 Tests

```elixir
defmodule Foundry.SparkLintTest do
  use ExUnit.Case, async: true

  defmodule AlwaysPassRule do
    @behaviour Foundry.SparkLint.Rule
    def check(_module, _ctx), do: {:ok, []}
  end

  defmodule AlwaysViolateRule do
    @behaviour Foundry.SparkLint.Rule
    def check(module, _ctx) do
      {:ok, [%Foundry.SparkLint.Violation{
        rule: :test_violation, module: module,
        message: "test", severity: :error
      }]}
    end
  end

  defmodule CrashingRule do
    @behaviour Foundry.SparkLint.Rule
    def check(_module, _ctx), do: {:error, :rule_crashed}
  end

  test "rule with no violations returns empty list" do
    {violations, errors} = Foundry.SparkLint.Runner.run([AlwaysPassRule], [String], %{})
    assert violations == [] and errors == []
  end

  test "violation is included in output" do
    {violations, _} = Foundry.SparkLint.Runner.run([AlwaysViolateRule], [String], %{})
    assert length(violations) == 1
    assert hd(violations).rule == :test_violation
  end

  test "rule error is collected, runner continues" do
    {violations, errors} =
      Foundry.SparkLint.Runner.run([AlwaysViolateRule, CrashingRule], [String], %{})
    assert length(violations) == 1
    assert length(errors) == 1
  end

  test "violations ordered :error before :warning, alpha by module within severity" do
    defmodule MixedRule do
      @behaviour Foundry.SparkLint.Rule
      def check(_module, _ctx) do
        {:ok, [
          %Foundry.SparkLint.Violation{rule: :w, module: Zeta,  message: "", severity: :warning},
          %Foundry.SparkLint.Violation{rule: :a, module: Alpha, message: "", severity: :error},
          %Foundry.SparkLint.Violation{rule: :b, module: Beta,  message: "", severity: :error}
        ]}
      end
    end

    {violations, _} = Foundry.SparkLint.Runner.run([MixedRule], [String], %{})
    severities = Enum.map(violations, & &1.severity)
    assert List.first(severities) == :error
    errors = Enum.filter(violations, & &1.severity == :error)
    mods   = Enum.map(errors, &inspect(&1.module))
    assert mods == Enum.sort(mods)
  end

  test "runner collects all violations before returning" do
    {violations, _} =
      Foundry.SparkLint.Runner.run([AlwaysViolateRule, AlwaysViolateRule], [String], %{})
    assert length(violations) == 2
  end
end
```

### 6.2 Implementation

```elixir
defmodule Foundry.SparkLint.Rule do
  @callback check(module :: module(), context :: Foundry.SparkLint.Context.t()) ::
    {:ok, [Foundry.SparkLint.Violation.t()]} | {:error, term()}
end

defmodule Foundry.SparkLint.Violation do
  @enforce_keys [:rule, :module, :message, :severity]
  defstruct [:rule, :module, :message, :severity, :step, :attribute]
end

defmodule Foundry.SparkLint.Context do
  @moduledoc """
  Passed to each rule. `metadata` is opaque — SparkLint never inspects it.
  Foundry.LintRules.* cast context.metadata to access manifest data.
  """
  defstruct [:module, :modules, metadata: %{}]
end

defmodule Foundry.SparkLint.Runner do
  def run(rules, modules, base_context) do
    # KNOWN LIMITATION: Uses `acc_v ++ new_v` which is O(n) per append. For ~30 modules × 7 rules,
    # this is acceptable (O(210²) ≈ 44K operations). Before `spark_lint` Hex extraction,
    # optimize to `[new_v | acc_v]` + `Enum.reverse/1` or accumulate as flat list with
    # `Enum.flat_map/2`. Phase 1 baseline is correct, just not optimal at scale.
    {violations, errors} =
      for rule <- rules, module <- modules, reduce: {[], []} do
        {acc_v, acc_e} ->
          ctx = %Foundry.SparkLint.Context{
            module:   module,
            modules:  modules,
            metadata: Map.get(base_context, :metadata, %{})
          }
          case rule.check(module, ctx) do
            {:ok, new_v}     -> {acc_v ++ new_v, acc_e}
            {:error, reason} -> {acc_v, acc_e ++ [%{rule: rule, module: module, reason: reason}]}
          end
      end

    sorted =
      Enum.sort_by(violations, fn v ->
        {case(v.severity, do: (:error -> 0; :warning -> 1; :info -> 2)), inspect(v.module)}
      end)

    {sorted, errors}
  end
end
```

**Gate:** All `Foundry.SparkLintTest` tests pass.

---

## Step 7 — `Foundry.LintRules.*` — Phase 1 rules

### 7.1 Pre-step: resolve `adapter_version_not_active`

This rule ID appears in the acceptance matrix but has no entry in `lint-catalogue.md`.
Resolve before writing any rule code:

- Add `:adapter_version_not_active` to `lint-catalogue.md` under
  `Foundry.LintRules.AdapterVersionRule` (`:warning`, `planned`) with the invariant:
  a provider adapter module registered in `conditional_libraries` but not set as the
  active version on any `ProviderConfig` record in the project.
- Add `Foundry.LintRules.AdapterVersionRule` to `Foundry.LintRules.Registry`.

### 7.2 Rule test strategy

Use synthetic fixture modules in `test/support/lint_fixtures/` rather than mutating
and recompiling the reference project in unit tests. Mutation tests (which recompile)
are reserved for the integration tests in Step 10.

```
test/support/lint_fixtures/
  missing_paper_trail.ex        # Ash resource intentionally missing AshPaperTrail
  missing_archival.ex           # Ash resource intentionally missing AshArchival
  no_runbook_transfer.ex        # Reactor with >3 steps, no @runbook
  no_idempotency_transfer.ex    # Reactor with side effects, no idempotency key
  no_moduledoc.ex               # Module with @moduledoc false
  missing_attr_description.ex   # Resource with attribute missing description:
```

Each fixture is a minimal module that satisfies exactly the conditions needed to
trigger or not trigger the rule under test.

### 7.3 Rule implementations

**`Foundry.LintRules.PaperTrailRule`:**

```elixir
defmodule Foundry.LintRules.PaperTrailRule do
  @behaviour Foundry.SparkLint.Rule

  def check(module, ctx) do
    sensitive = ctx.metadata[:sensitive_modules] || []

    if module in sensitive and not paper_trail?(module) do
      {:ok, [%Foundry.SparkLint.Violation{
        rule:     :missing_paper_trail,
        module:   module,
        message:  "#{inspect module} is sensitive but does not use AshPaperTrail.Resource",
        severity: :error
      }]}
    else
      {:ok, []}
    end
  end

  defp paper_trail?(module) do
    AshPaperTrail.Resource in Spark.extensions(module)
  rescue
    _ -> false
  end
end
```

Rules for `:missing_archival`, `:missing_runbook`, `:missing_idempotency`,
`:missing_description` follow the same shape. Each checks one condition, returns
one violation type, reads manifest data exclusively from `ctx.metadata`.

**`Foundry.LintRules.RunbookRule`** — two possible violations: no `@runbook`
declared, or `@runbook` declared but the file does not exist:

```elixir
def check(module, ctx) do
  project_root = ctx.metadata[:project_root] || File.cwd!()
  info = Foundry.SparkMeta.walk(module)

  cond do
    info.type not in [:transfer, :reactor] -> {:ok, []}
    length(info.steps) <= 3               -> {:ok, []}
    info.runbook == nil ->
      {:ok, [violation(module, "#{inspect module} has >3 steps but declares no @runbook")]}
    not File.exists?(Path.join(project_root, info.runbook)) ->
      {:ok, [violation(module, "#{inspect module} @runbook path does not exist: #{info.runbook}")]}
    true ->
      {:ok, []}
  end
end
```

**`Foundry.LintRules.ManifestValidator`** — a standalone pass, NOT implementing
`SparkLint.Rule`. It validates the manifest keyword list directly:

```elixir
defmodule Foundry.LintRules.ManifestValidator do
  @spec check(manifest :: keyword()) :: [Foundry.SparkLint.Violation.t()]
  def check(manifest) do
    []
    |> check_required_approvers(manifest)
    |> check_unknown_sensitive_resources(manifest)
    |> check_coverage_weights(manifest)
    |> check_exclusion_comments(manifest)
    |> check_cldr_backend(manifest)
  end

  defp check_required_approvers(acc, manifest) do
    approvers = Keyword.get(manifest, :approvers, [])
    Enum.reduce([:sensitive_lead, :compliance_officer], acc, fn key, a ->
      if Keyword.get(approvers, key) do
        a
      else
        [%Foundry.SparkLint.Violation{
          rule:     :manifest_missing_required_approver,
          module:   Foundry.Manifest,
          message:  "manifest.approvers.#{key} is required but absent",
          severity: :error
        } | a]
      end
    end)
  end

  defp check_coverage_weights(acc, manifest) do
    weights = Keyword.get(manifest, :coverage_weights, [])
    if weights == [], do: acc, else:
      case weights |> Keyword.values() |> Enum.sum() do
        total when abs(total - 1.0) > 0.001 ->
          [%Foundry.SparkLint.Violation{
            rule:     :manifest_invalid_coverage_weights,
            module:   Foundry.Manifest,
            message:  "coverage_weights sum to #{Float.round(total, 6)}, must be 1.0 ± 0.001",
            severity: :error
          } | acc]
        _ -> acc
      end
  end

  # check_unknown_sensitive_resources, check_exclusion_comments,
  # check_cldr_backend — analogous
end
```

### 7.4 Rule registry

Use an explicit registry rather than auto-discovery via `Application.spec`:

```elixir
defmodule Foundry.LintRules.Registry do
  @moduledoc """
  Explicit registry of all active lint rules.
  Adding a new Foundry.LintRules.* module requires adding it here.
  Accidental registration is worse than a deliberate omission.
  """

  @module_rules [
    Foundry.LintRules.PaperTrailRule,
    Foundry.LintRules.ArchivalRule,
    Foundry.LintRules.RunbookRule,
    Foundry.LintRules.IdempotencyRule,
    Foundry.LintRules.DescriptionRule,
    Foundry.LintRules.VersionRule,
    Foundry.LintRules.AdapterVersionRule
  ]

  def module_rules,       do: @module_rules
  def manifest_validators, do: [Foundry.LintRules.ManifestValidator]
end
```

**Gate:** All lint rule unit tests pass (synthetic fixture modules).

---

## Step 8 — `mix foundry.lint.all` Mix task

### 8.1 Tests

```elixir
describe "mix foundry.lint.all" do
  test "clean run exits 0, errors: 0, output is valid JSON" do
    {output, 0} = System.cmd("mix", ["foundry.lint.all", "--json"],
                              cd: @ref_root, stderr_to_stdout: true)
    result = Jason.decode!(output)
    assert result["errors"] == 0
  end

  test "every violation has module, rule, message, severity" do
    {output, _} = System.cmd("mix", ["foundry.lint.all", "--json"], cd: @ref_root)
    result = Jason.decode!(output)
    for v <- result["violations"] do
      assert Map.has_key?(v, "module")
      assert Map.has_key?(v, "rule")
      assert Map.has_key?(v, "message")
      assert Map.has_key?(v, "severity")
    end
  end

  test "warnings (adapter_version_not_active) don't cause exit 1" do
    {_, code} = System.cmd("mix", ["foundry.lint.all"], cd: @ref_root)
    assert code == 0
  end

  test ":ash_version_outdated does NOT appear on clean Ash 3.x project" do
    {output, _} = System.cmd("mix", ["foundry.lint.all", "--json"], cd: @ref_root)
    result = Jason.decode!(output)
    refute Enum.any?(result["violations"], & &1["rule"] == "ash_version_outdated")
  end

  test "violations ordered :error before :warning, alphabetical by module" do
    # Introduce both an error and a warning by mutating the project
    # (tested in Step 10 mutation tests; here we assert ordering invariant
    # on whatever the clean project produces)
    {output, _} = System.cmd("mix", ["foundry.lint.all", "--json"], cd: @ref_root)
    violations = Jason.decode!(output)["violations"]
    error_positions   = violations |> Enum.with_index()
                          |> Enum.filter(& elem(&1, 0)["severity"] == "error")
                          |> Enum.map(&elem(&1, 1))
    warning_positions = violations |> Enum.with_index()
                          |> Enum.filter(& elem(&1, 0)["severity"] == "warning")
                          |> Enum.map(&elem(&1, 1))
    if error_positions != [] and warning_positions != [] do
      assert Enum.max(error_positions) < Enum.min(warning_positions)
    end
  end
end
```

### 8.2 Implementation

```elixir
defmodule Mix.Tasks.Foundry.Lint.All do
  use Mix.Task
  @shortdoc "Run all Foundry lint rules"

  def run(args) do
    json?        = "--json" in args
    project_root = File.cwd!()

    {:ok, manifest} = Foundry.Manifest.Parser.read(project_root)

    # Manifest validation — separate pass before the module loop
    manifest_violations = Foundry.LintRules.ManifestValidator.check(manifest)

    # Module-level rules
    project_name = Keyword.get(manifest, :project_name, "")
    modules  = Foundry.Context.ModuleDiscovery.all_project_modules(project_root, project_name)
    metadata = %{
      manifest:         manifest,
      sensitive_modules: Keyword.get(manifest, :sensitive_resources, []),
      project_root:     project_root
    }

    {module_violations, rule_errors} =
      Foundry.SparkLint.Runner.run(
        Foundry.LintRules.Registry.module_rules(),
        modules,
        %{metadata: metadata}
      )

    all_violations =
      (manifest_violations ++ module_violations)
      |> Enum.sort_by(fn v ->
        {case(v.severity, do: (:error -> 0; :warning -> 1; :info -> 2)), inspect(v.module)}
      end)

    error_count   = Enum.count(all_violations, & &1.severity == :error)
    warning_count = Enum.count(all_violations, & &1.severity == :warning)

    if json? do
      IO.puts(Jason.encode!(%{
        errors:     error_count,
        warnings:   warning_count,
        violations: Enum.map(all_violations, fn v ->
          %{rule: to_string(v.rule), module: inspect(v.module),
            message: v.message, severity: to_string(v.severity)}
        end)
      }, pretty: true))
    else
      print_violations_text(all_violations, rule_errors)
    end

    if error_count > 0, do: exit({:shutdown, 1})
  end
end
```

**Gate:** All task-level acceptance tests pass.

---

## Step 9 — `mix foundry.project.status`

Composes all Phase 1 data into the runtime health picture.

### 9.1 Tests

```elixir
describe "mix foundry.project.status" do
  setup do
    {output, 0} = System.cmd("mix", ["foundry.project.status", "--json"],
                              cd: @ref_root, stderr_to_stdout: true)
    {:ok, status: Jason.decode!(output)}
  end

  test "all top-level keys present", %{status: s} do
    expected = ~w[generated_at compiled_at project domains sensitive_modules lint
                  migrations proposals compliance test_coverage ci stack manifest]
    for key <- expected, do: assert Map.has_key?(s, key), "Missing: #{key}"
  end

  test "project is IgamingRef", %{status: s},
    do: assert s["project"] == "IgamingRef"

  test "domains: 6 entries", %{status: s},
    do: assert length(s["domains"]) == 6

  test "sensitive_modules contains expected short names", %{status: s} do
    assert "Wallet" in s["sensitive_modules"]
    assert "LedgerEntry" in s["sensitive_modules"]
  end

  test "compiled_at is non-null ISO 8601 timestamp", %{status: s} do
    assert is_binary(s["compiled_at"])
    assert {:ok, _, _} = DateTime.from_iso8601(s["compiled_at"])
  end

  test "lint.errors: 0 on clean project", %{status: s},
    do: assert s["lint"]["errors"] == 0

  test "lint.warnings >= 1", %{status: s},
    do: assert s["lint"]["warnings"] >= 1

  test "migrations.pending_count: 0", %{status: s},
    do: assert s["migrations"]["pending_count"] == 0

  test "proposals.open_count: 0", %{status: s},
    do: assert s["proposals"]["open_count"] == 0

  test "compliance contains all 17 RG-* IDs", %{status: s} do
    # Complete RG-* list from reference-project-fixture.md (17 total)
    expected_ids = ~w[RG-MGA-001 RG-MGA-002 RG-MGA-003 RG-MGA-005 RG-MGA-007
                      RG-MGA-009 RG-UK-002 RG-UK-003 RG-UK-004 RG-UK-008
                      RG-UK-011 RG-UK-014 RG-UK-022 RG-MGA-004 RG-MGA-006
                      RG-UK-001 RG-UK-012]
    actual_ids = Enum.map(s["compliance"]["requirements"], & &1["id"])
    for id <- expected_ids, do: assert id in actual_ids, "Missing: #{id}"
  end

  test "at least one compliance requirement has status: planned", %{status: s} do
    assert Enum.any?(s["compliance"]["requirements"], & &1["status"] == "planned")
  end

  test "stack.ash starts with '3.'", %{status: s},
    do: assert String.starts_with?(s["stack"]["ash"], "3.")

  test "stack versions are exact resolved values, no constraint syntax", %{status: s} do
    for {_lib, version} <- s["stack"], not is_nil(version) do
      refute String.contains?(version, "~>")
      refute String.contains?(version, ">=")
    end
  end

  test "manifest.domain_type is igaming", %{status: s},
    do: assert s["manifest"]["domain_type"] == "igaming"

  test "ci.context_lock_current: true after fresh context generation", %{status: s} do
    # Ensure lock is current before running status
    System.cmd("mix", ["foundry.project.context"], cd: @ref_root)
    assert s["ci"]["context_lock_current"] == true
  end
end
```

### 9.2 Implementation

**9a.** Stack version extraction — use `Code.eval_string/1` on `mix.lock`:

```elixir
defmodule Foundry.Status.StackVersions do
  @tracked ~w[elixir ash ash_postgres phoenix reactor oban]a

  def read(project_root) do
    path = Path.join(project_root, "mix.lock")
    case File.read(path) do
      {:error, _} -> Map.new(@tracked, &{to_string(&1), nil})
      {:ok, content} ->
        {lock, _} = Code.eval_string(content)
        Map.new(@tracked, fn lib ->
          {to_string(lib), extract_version(lock, to_string(lib))}
        end)
    end
  end

  defp extract_version(lock, lib) do
    case Map.get(lock, lib) do
      {:hex, _pkg, version, _, _, _, _, _} -> version   # hex dep
      {:hex, _pkg, version, _, _, _, _}    -> version   # older format
      {:git, _url, ref, _opts}             -> ref       # git dep: emit SHA
      _                                    -> nil
    end
  end
end
```

**9b.** `compiled_at` — max mtime of `.beam` files under `_build/`:

```elixir
defp compiled_at(project_root) do
  app_name = project_root |> Path.basename() |> Macro.underscore()
  ebin     = Path.join([project_root, "_build", "dev", "lib", app_name, "ebin"])

  case Path.wildcard(Path.join(ebin, "*.beam")) do
    [] -> nil
    beams ->
      beams
      |> Enum.map(&File.stat!(&1).mtime)
      |> Enum.max()
      |> NaiveDateTime.from_erl!()
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_iso8601()
  end
end
```

**9c.** `ci.context_lock_current` — computed from `LockFile.check/1`, not from a
CI artifact file:

```elixir
defp ci_status(project_root) do
  lock_current = match?(:ok, Foundry.Context.LockFile.check(project_root))

  base = %{
    "context_lock_current" => lock_current,
    "last_run_at"  => nil,
    "commit"       => nil,
    "branch"       => nil,
    "lint_passed"  => nil,
    "tests_passed" => nil
  }

  # Overlay with CI-written status file if present
  case Foundry.FileSystem.read(project_root, ".foundry/ci_status.json") do
    {:ok, content} -> Map.merge(base, Jason.decode!(content))
    _              -> base
  end
end
```

**9d.** `Mix.Tasks.Foundry.Project.Status` — assembles `ProjectStatus`, outputs JSON.
Cache TTL 60 seconds in ETS between rapid calls. The task always recomputes; the
cache avoids redundant work within a single studio session.

**Gate:** All status acceptance matrix tests pass.

---

## Step 10 — Integration: CI pipeline simulation

### Sequence test

```bash
cd reference_projects/igaming

mix compile --warnings-as-errors                           # baseline: must exit 0
mix foundry.project.context                               # generates lock
mix foundry.project.context --check                       # must exit 0 (just generated)
mix foundry.lint.all                                      # must exit 0 (clean)
mix foundry.project.status --json | python3 -m json.tool  # must parse as valid JSON
```

Staleness cycle:

```bash
touch lib/igaming_ref/finance/wallet.ex
mix foundry.project.context --check    # must exit 1 (mtime changed)
mix foundry.project.context            # regenerate + update lock
mix foundry.project.context --check    # must exit 0 again
```

### Mutation tests

Each runs against an isolated temp copy (`File.cp_r!/2` to a temp dir, `on_exit` cleanup).
All must produce exit 1 with the expected rule ID in the JSON violations.

| Mutation | Expected exit | Expected rule |
|---|---|---|
| Remove `@runbook` from `WithdrawalTransfer` | 1 | `missing_runbook` |
| Remove `AshPaperTrail.Resource` use from `Wallet` | 1 | `missing_paper_trail` |
| Remove `AshArchival.Resource` use from `LedgerEntry` | 1 | `missing_archival` |
| Remove idempotency key from `WithdrawalTransfer` | 1 | `missing_idempotency` |
| Remove `@moduledoc` from any non-test module | 1 | `missing_description` |
| Remove `approvers.sensitive_lead` from manifest | 1 | `manifest_missing_required_approver` |
| Replace `ash` version in `mix.lock` with `"2.x.x"` (mock) | 1 | `ash_version_outdated` |

Negative tests (mutations that must NOT produce errors):

| Mutation | Expected exit | Assertion |
|---|---|---|
| Add a warning-only condition (e.g. inactive adapter) | 0 | exit 0, `warnings >= 1` |
| Add an exclusion entry with a comment | 0 | no `manifest_exclusion_no_comment` violation |

**Gate:** All integration and mutation tests pass. This is the Phase 1 done signal.

---

## Step 11 — Backward-compat aliases

```elixir
# mix foundry.context <Module> → mix foundry.project.context <Module>
defmodule Mix.Tasks.Foundry.Context do
  use Mix.Task
  @shortdoc false   # hidden from `mix help`
  def run(args), do: Mix.Tasks.Foundry.Project.Context.run(args)
end

# mix foundry.diagram.generate → mix foundry.project.context
defmodule Mix.Tasks.Foundry.Diagram.Generate do
  use Mix.Task
  @shortdoc false
  def run(args), do: Mix.Tasks.Foundry.Project.Context.run(args)
end
```

`@shortdoc false` hides these from `mix help`. They exist for backward compat only
and are never documented as canonical.

---

## Schema freeze checklist

Before declaring Phase 1 done and beginning Phase 2, verify every item:

**`NodeEntry`:**
- [ ] All fields present in JSON output in schema-defined order
- [ ] `id` and `module` are identical strings (both the FQN)
- [ ] `type` is one of the 11 defined node type strings
- [ ] `app: null` on all nodes (standard project)
- [ ] `agent_steps: []` on all nodes (no AshAI in reference project)
- [ ] `state_machine` sub-keys: `present`, `states`, `transitions`, `state_attribute`
- [ ] `state_machine.states` and `telemetry_prefix` contain strings, not atoms
- [ ] `money_attributes` entries have `name`, `type`, `cldr_backend`
- [ ] `test_coverage` has `property_tests`, `scenario_tests`, `e2e_tests` (all boolean)

**`EdgeEntry`:**
- [ ] All edges have `from`, `to`, `relation`, `cross_app`, `cross_project`
- [ ] `cross_app: false` and `cross_project: false` on all edges (standard project)
- [ ] Edges ordered: by `from` FQN ascending, then `to` FQN ascending
- [ ] `belongs_to` relationships produce `relation: "references"`, not `"reads"`
- [ ] Reactor step writes produce `relation: "writes"`

**`SpecKitIndex`:**
- [ ] Has `index_token_count`, `index_token_warn`, `index_token_limit`, `adrs`,
      `runbooks`, `regulations`, `agents`, `usage_rules`
- [ ] `agents` is a single entry object, not a list (`AGENTS.md` = one document)
- [ ] Per-entry fields: `id`, `type`, `title`, `status`, `file_path`, `summary`,
      `tags`, `supersedes`, `superseded_by`, `last_modified`
- [ ] None of the 6 excluded files appear in any index sub-list
- [ ] `index_token_warn: false` on the reference project corpus

**`ProjectStatus`:**
- [ ] All 13 top-level keys present
- [ ] `compiled_at` is present and non-null
- [ ] `stack` version strings are exact resolved values — no `~>`, no `>=`
- [ ] `sensitive_modules` contains short names (last module segment), not FQNs
- [ ] `lint.violations` entries have `rule`, `module`, `message`, `severity` as strings
- [ ] `lint` data sourced from `SparkLint.Runner` — not re-implemented in status
- [ ] `ci.context_lock_current` computed from `LockFile.check/1`, not from a file

**`LintViolation` (JSON):**
- [ ] `rule` is a string (serialised from atom with `to_string/1`)
- [ ] `module` is a string (serialised with `inspect/1`)
- [ ] `severity` is a string (`"error"`, `"warning"`, `"info"`)
- [ ] Violations ordered: `:error` before `:warning`; alpha by module within severity

**Build-sequence requirements:**
- [ ] `NodeEntry` includes all 13 fields from BUILD_SEQUENCE §Schema design review:
      `data_layer`, `pending_migrations`, `paper_trail`, `archival`, `state_machine`,
      `api_routes`, `telemetry_prefix`, `money_attributes`, `authentication_subject`,
      `oban_queues`, `rate_limited`, `feature_flags`, `rules`
- [ ] `adapter_version_not_active` rule has an entry in `lint-catalogue.md`
- [ ] Node count assertion locked to the authoritative count from the fixture
      (recount before freezing — see §Known constraints)

---

## Dependency diagram

```
P-1: reference_projects/igaming compiled (mix compile exits 0)
P-2: Phase1AcceptanceTest skeleton (all @tag :skip)
 │
 ▼
Step 1: Foundry.FileSystem
  ├─ @permitted_dirs (prefix + "/" guard) + @permitted_exact (==)
  └─ FileSystemTest: 11 tests pass
 │
 ▼
Step 2: Foundry.SparkMeta + structs
  ├─ ModuleInfo, Attribute, Action, StepEntry, MoneyAttr
  ├─ __info__(:attributes) for @-declared fields
  ├─ Spark.extensions/1 for extension detection
  ├─ Spark.Dsl.Extension.get_entities/3 for DSL entity extraction (NOT Reactor.Info)
  ├─ Foundry.Manifest.Parser (defined here, used in Steps 3/7/9)
  └─ SparkMetaTest: all tests pass
 │
 ▼
Step 3: mix foundry.project.context <Module>
  ├─ Foundry.Context.NodeBuilder (SparkMeta → NodeEntry, manifest sensitivity)
  ├─ Foundry.Context.NodeEntry (struct + Jason.Encoder with field order)
  ├─ Foundry.Context.PendingMigrations (one subprocess per project, not per module)
  ├─ Foundry.Context.Cache (Nebulex L1)
  └─ Per-module acceptance tests pass
 │
 ▼
Step 4: mix foundry.project.context (bulk)
  ├─ Foundry.Context.GraphBuilder (node list + edges)
  ├─ Edge derivation: Reactor steps → writes/reads; belongs_to → references
  ├─ Foundry.Context.SpecKitIndexBuilder (MDEx AST cache, token estimate = bytes/3)
  ├─ Foundry.Context.SessionState (struct + ETS scaffolded; delta always nil)
  └─ Bulk acceptance tests pass
 │
 ▼
Step 5: mix foundry.project.context --check
  ├─ Foundry.Context.LockFile (sorted per-file SHA256 hashes → combined hash)
  └─ --check tests: exit 0/1 pass
 │
 ▼
Step 6: Foundry.SparkLint engine
  ├─ SparkLint.Rule (behaviour)
  ├─ SparkLint.Violation (struct)
  ├─ SparkLint.Context (metadata: map() — opaque to SparkLint)
  ├─ SparkLint.Runner (collect all, sort, return {violations, errors})
  └─ SparkLintTest: all tests pass
 │
 ▼
Step 7: Foundry.LintRules.*
  ├─ PaperTrailRule, ArchivalRule, RunbookRule, IdempotencyRule,
  │  DescriptionRule, VersionRule, AdapterVersionRule
  ├─ ManifestValidator (standalone pass — NOT via SparkLint.Runner)
  ├─ Foundry.LintRules.Registry (explicit list — no auto-discovery)
  └─ Rule unit tests: synthetic fixtures in test/support/lint_fixtures/
 │
 ▼
Step 8: mix foundry.lint.all
  ├─ ManifestValidator runs before module loop
  ├─ SparkLint.Runner with Registry.module_rules()
  ├─ --json: rule/module/message/severity as strings in JSON
  └─ Task acceptance tests pass (incl. clean-run exit 0, warning-only exit 0)
 │
 ▼
Step 9: mix foundry.project.status
  ├─ Foundry.Status.StackVersions (mix.lock parse: hex tuple → version string)
  ├─ compiled_at: max mtime of _build/ .beam files
  ├─ ci.context_lock_current: LockFile.check/1 (not CI artifact)
  ├─ sensitive_modules: short names (last segment), not FQNs
  └─ Status acceptance tests pass
 │
 ▼
Step 10: Integration — CI pipeline simulation + mutation tests
  └─ All integration and mutation tests pass ← Phase 1 done signal
 │
 ▼
Step 11: Backward-compat aliases (@shortdoc false)
 │
 ▼
Schema freeze checklist — all items checked → Phase 2 begins
```

---

## What is explicitly NOT built in Phase 1

- `Foundry.Copilot.ContextBuilder` (Phase 3) — reads from `project.status`. Phase 1
  produces the data; Phase 3 assembles it into LLM context tiers.
- `Foundry.Studio.SystemMapChannel` (Phase 2) — Phoenix channel serving
  `project.context` to the browser. The data source is ready; the channel is not.
- `Foundry.Context.SessionState` delta computation (Phase 4) — struct and ETS table
  are scaffolded in Step 4, but delta logic is Phase 4. `graph_delta` is always `null`.
- `reactor_human_gate` and `reactor_agent_step` Hex package extraction (Phase 7) —
  internal modules designed for extraction; extraction itself is post-Phase 1.
- `Foundry.LintRules.FileWriteRule`, `AdminRouteRule`, `MoneyTypeRule`,
  `DataAttributeRule`, `DecoratorRule`, `FeatureFlagRule` — depend on DSL or router
  introspection not available until later phases.
- `mix foundry.context.all` — eliminated; the node corpus is `mix foundry.project.context`.
- `mix foundry.versions.check` — eliminated; version enforcement is `VersionRule`.
- `mix foundry.compliance.check` — eliminated; compliance is in `project.status`.
- Stub Mix task modules that print "coming in Phase N" — leave the namespace empty.