# Runbook: Project Server Unavailable

**Applies to:** `Foundry.Project.Reader` and all dependent components  
**Last tested:** —  
**Escalation:** Platform team

---

## Symptoms

- Studio UI shows "Unable to connect to project" 
- System map fails to load
- Copilot cannot build context (returns `:context_build_failed`)
- `mix foundry.context <Module>` times out

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
mix foundry.context Foundry.Finance.BetTransfer

# Get compliance coverage
mix foundry.compliance.check

# Get system diagram data
mix foundry.diagram.generate --json
```

These run Mix tasks directly against the project. They are what the Studio calls internally.
The Studio being unavailable does not remove development capability — it removes the UI layer.