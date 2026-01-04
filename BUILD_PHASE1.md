# Plasmodium v2 - Phase 1 Build Plan

## Goal

Minimal viable system: human creates task → owner spawns → owner creates phase → role agents spawn → discussion happens → phase closes → agents exit.

No subtasks, no dashboard, no git integration. Just the core loop.

---

## What We're Building

```
Human: pm task "Build a cool website"
  → Owner @cedar_a1b2 spawns

Owner: pm phase "Brainstorm" --limit 8 --roles designer,dev
  → @oak_c3d4 (designer) spawns
  → @pine_e5f6 (dev) spawns

All agents: pm chat / pm say "..."
  → Messages append to JSONL
  → Phase auto-closes at 8 messages

Role agents: detect phase closed → exit
Owner: synthesize, do work, pm done
```

---

## Tasks

### 1. Project Structure
- [ ] Clean out old v1 code (keep DESIGN.md, BUILD_PHASE1.md)
- [ ] Create new directory structure:
  ```
  plasmodium/
    pm                    # Main CLI entry point (bash)
    lib/
      core.sh             # Core functions
      commands/           # One file per command
    prompts/
      owner.md            # Owner agent prompt
      roles/
        designer.md
        developer.md
        pm.md
    DESIGN.md
    BUILD_PHASE1.md
  ```

### 2. `pm init`
- [ ] Create `.plasmodium/` directory
- [ ] Create `config.json` with project path
- [ ] Create `agents.json` (empty)
- [ ] Create `tasks/` directory

### 3. `pm task "description"`
- [ ] Generate task ID (tk-XXXXXX)
- [ ] Create task directory `.plasmodium/tasks/tk-XXXXXX/`
- [ ] Write `task.json` with description, status: "active"
- [ ] Generate owner name (tree_XXXX pattern)
- [ ] Spawn owner agent with prompt
- [ ] Register agent in `agents.json`

### 4. `pm status`
- [ ] List all tasks with status
- [ ] List all active agents
- [ ] Show current phase for each task (if any)

### 5. `pm phase "Name" --limit N --roles r1,r2`
- [ ] Validate: caller is owner of a task
- [ ] Generate phase ID (ph-XXXXXX)
- [ ] Create phase directory with `phase.json`
- [ ] Create empty `messages.jsonl`
- [ ] For each role: spawn role agent with role-specific prompt
- [ ] Register role agents in `agents.json`

### 6. `pm chat`
- [ ] Find current phase for calling agent
- [ ] Read and display `messages.jsonl`
- [ ] Show message count vs limit

### 7. `pm say "message"`
- [ ] Find current phase for calling agent
- [ ] Check if phase is still active (message count < limit)
- [ ] Append message to `messages.jsonl`
- [ ] If message count == limit: mark phase as closed

### 8. `pm end-phase`
- [ ] Validate: caller is owner
- [ ] Mark phase as closed in `phase.json`

### 9. `pm done`
- [ ] Validate: caller is owner
- [ ] Mark task as done in `task.json`
- [ ] Clean up: remove owner from `agents.json`

### 10. Agent Spawning
- [ ] Function to spawn Claude Code instance with prompt
- [ ] Use `--dangerously-skip-permissions` flag
- [ ] Pass environment variables: PM_CLI, WORKER_NAME, TASK_ID, PHASE_ID, ROLE
- [ ] Background the process, capture PID
- [ ] Register in `agents.json` with PID

### 11. Agent Prompts
- [ ] Owner prompt with Quick Reference, Workflow, Critical Rules
- [ ] Role prompts (designer, developer, pm) with opinions baked in
- [ ] Template substitution for {NAME}, {TASK}, {PHASE}, etc.

### 12. Agent Detection
- [ ] Agents need to know who they are (env var or file)
- [ ] Agents need to find their current phase
- [ ] Agents need to detect when phase closes (poll messages.jsonl count)

---

## Out of Scope (Phase 1)

- `pm subtask` / `pm wait-children`
- `pm history`
- `pm extend-phase`
- `pm kill`
- `pm dashboard`
- Git integration
- Health checks / auto-respawn
- Blockers / dependencies
- Adaptive polling (use fixed 5s for now)

---

## Implementation Order

1. **Project structure** - clean slate
2. **pm init** - can initialize a project
3. **pm task** - can create task (no spawning yet)
4. **pm status** - can see tasks
5. **Agent spawning** - get Claude Code instances running
6. **pm phase** - can create phase (spawns role agents)
7. **pm chat / pm say** - messaging works
8. **pm end-phase / pm done** - can close things
9. **Full integration test** - run the whole flow

---

## Test Scenario

```bash
cd ~/test-project
pm init
pm task "Create a simple landing page"

# Watch the magic happen:
# - Owner spawns, thinks about task
# - Owner creates a design phase
# - Designer and dev spawn
# - They discuss
# - Phase closes
# - Owner synthesizes and implements
# - Owner marks done
```

---

## Let's Go

Starting with task 1: Project Structure.
