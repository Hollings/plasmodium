# Plasmodium v2 Design

## Core Metaphor

Slime mold + fungi lifecycle:
- **Spore** = unit of work
- **Plasmodium** = exploration phase (figure out what to do)
- **Mycelium** = execution phase (do the work)
- **Fruit** = completed output
- **Signal** = public communication between workers

## Current State (implemented)

- `pm` CLI with: new, claim, explore, execute, split, fruit, ripen, signal, signals, status, spawn, plan, approve, reject
- Workers are Claude Code instances with `--dangerously-skip-permissions`
- Spores stored in `.plasmodium/spores.jsonl` (append-only, last wins)
- Signals stored in `.plasmodium/signals.log`
- Workers stored in `.plasmodium/workers.json`
- Dashboard at `.plasmodium/dashboard.html` with server.py for task submission
- Parent/child spores with auto-ripening when children complete
- **Dependencies**: `pm new --depends sp-xxx` creates blocked spores that auto-unblock
- **Plan/Approval**: Workers must get plans approved before executing
- **Review spores**: Reviews are spores themselves (type: "review")
- **Auto-spawn**: Hook-based spawning when work is created:
  - Human creates spore → spawns 1 worker
  - `pm plan --approvals N` → spawns N workers for review
- Worker logs in `.plasmodium/logs/`

## Remaining Features

### Gates (Hooks)

Shell scripts that run at lifecycle points:
```
.plasmodium/
└── gates/
    ├── pre-execute/
    │   └── require-approval.sh   # blocks if not approved
    ├── pre-fruit/
    │   ├── require-branch.sh     # must be on feature branch
    │   └── require-tests.sh      # tests must pass
    └── post-fruit/
        └── notify.sh             # optional notifications
```

Gates return 0 (pass) or non-zero (fail). `pm execute` and `pm fruit` run appropriate gates.

### 7. Worker Pool Model

- Workers choose their own work from available tasks
- Priority: reviews > unblocked spores > raw spores
- Workers spawn more workers if needed: `pm spawn`
- Workers stay alive between tasks (don't exit after each fruit)
- When truly idle (no work), worker goes idle (not exit)

### 8. Updated Worker Prompt

Workers must:
1. Check for pending reviews first (highest priority)
2. Claim a spore
3. Explore (plasmodium phase)
4. Write plan with `pm plan --approvals N`
5. Wait for approval
6. Execute (mycelium phase)
7. Pass gates before fruiting
8. Fruit and look for next work

## Implementation Order

1. depends_on (unblocks sequential work)
2. docs folder structure
3. pm plan command
4. review spore creation
5. pm approve / pm reject
6. gates system
7. update worker prompt
8. worker pool behavior

## Key Principles

- **Reviews are spores** - makes them trackable, claimable work
- **Gates are hooks** - shell scripts, simple, flexible
- **Workers choose work** - no central assignment
- **Signals are public** - the audit trail and discussion forum
- **Everything in git** - spores, signals, docs, gates all versioned
