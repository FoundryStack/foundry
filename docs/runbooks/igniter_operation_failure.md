# Runbook: Igniter Operation Failure

**Applies to:** All scaffold operations in `FoundryStudio.Operations.*`  
**Last tested:** —  
**Escalation:** Platform team

---

## Symptoms

- Copilot shows "Scaffold operation failed" in the review panel
- `mix foundry.studio.scaffold` exits with non-zero status
- Proposed diff is empty or malformed
- Applied change results in a compilation error

---

## Step 1: Read the Operation Error

```bash
# Get the structured error from the last operation
mix foundry.studio.scaffold.last-error

# The output will include:
# - operation: which Op.* module failed
# - step: which step in the pipeline failed
# - reason: the Igniter error or AST parse error
# - dry_run_output: the partial diff before failure
```

---

## Step 2: AST Parse Error

If `reason` contains "failed to parse module" or "zipper could not find target":

```bash
# The target module may have a syntax issue that prevents Igniter from reading it
mix compile --force 2>&1 | head -30

# If compilation fails: fix the syntax error first, then retry the scaffold operation
# The scaffold operation is not the cause — it cannot apply to a module that doesn't compile
```

---

## Step 3: Operation Template Outdated

If `reason` contains "unknown DSL option" or "deprecated key":

The scaffold operation's template uses a DSL option that has changed in the current library version.

```bash
# Check which library version changed
mix foundry.studio.versions.check

# Compare the failing operation's template against current ExDoc
mix foundry.studio.docs.fetch ash Resource.Dsl.Attribute

# The operation template needs updating — this requires a platform team fix
# Workaround: make the change manually using the CLI pattern the operation would generate
```

To report: open an issue with `mix foundry.studio.scaffold.last-error --full` output attached.

---

## Step 4: Dry-Run Passes, Apply Fails

If the dry-run diff looks correct but applying it fails:

```bash
# Check for file permission issues
ls -la lib/  

# Check for concurrent modification (another process writing the same file)
# This is rare but can happen if the file watcher triggers a recompile during apply
mix foundry.studio.scaffold.retry --last-operation
```

If retry also fails: apply the dry-run diff manually.

```bash
# Get the clean diff
mix foundry.studio.scaffold.last-error --dry-run-diff > /tmp/proposed.patch

# Review and apply manually
patch -p1 < /tmp/proposed.patch
mix compile
mix foundry.studio.lint.all
```

---

# Runbook: Project Server Unavailable

**Applies to:** `FoundryStudio.Project.Reader` and all dependent components  
**Last tested:** —  
**Escalation:** Platform team

---

## Symptoms

- Studio UI shows "Unable to connect to project" 
- System map fails to load
- Copilot cannot build context (returns `:context_build_failed`)
- `mix foundry.studio.context <Module>` times out

---

## Step 1: Check Studio Process

```bash
# For local mode
ps aux | grep foundry.studio
# If not running: mix foundry.studio (in the project directory)

# Check for port conflict
lsof -i :4001
# If another process owns 4001: configure a different port in config/foundry_studio.exs
```

---

## Step 2: Check Project Compilation

The Project Server reads from compiled modules. If the project doesn't compile, it has no data.

```bash
mix compile
# If compilation fails: fix compilation errors first
# The Studio cannot display a system map for a project that doesn't compile
```

---

## Step 3: Check File Watcher

```bash
# Verify inotify limits (Linux only)
cat /proc/sys/fs/inotify/max_user_watches
# If < 8192: increase it
sudo sysctl fs.inotify.max_user_watches=65536
```

---

## Step 4: Manual Context Retrieval

While the Project Server is unavailable, context is still available via CLI:

```bash
# Get context for a specific module
mix foundry.studio.context Foundry.Finance.BetTransfer

# Get compliance coverage
mix foundry.studio.compliance.check

# Get system diagram data
mix foundry.studio.diagram.generate --json
```

These run Mix tasks directly against the project. They are what the Studio calls internally.
The Studio being unavailable does not remove development capability — it removes the UI layer.