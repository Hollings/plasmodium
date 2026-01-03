# Plasmodium v2 Design

## Core Metaphor

Slime mold + fungi lifecycle:
- **Spore** = unit of work
- **Plasmodium** = exploration phase (figure out what to do)
- **Mycelium** = execution phase (do the work)
- **Fruit** = completed output
- **Signal** = public communication between workers

## Current State (implemented)

- `pm` CLI with: new, claim, explore, execute, split, fruit, ripen, signal, signals, status, spawn
- Workers are Claude Code instances with `--dangerously-skip-permissions`
- Spores stored in `.plasmodium/spores.jsonl` (append-only, last wins)
- Signals stored in `.plasmodium/signals.log`
- Workers stored in `.plasmodium/workers.json`
- Dashboard at `.plasmodium/dashboard.html` with server.py for task submission
- Parent/child spores with auto-ripening when children complete

## Planned Features

### 1. Dependencies (`depends_on`)

Spores can depend on other spores:
```json
{
  "id": "sp-test",
  "task": "test the feature",
  "depends_on": ["sp-implement"],
  "status": "blocked"
}
```

- When sp-implement fruits → sp-test becomes "raw" (claimable)
- `pm new --depends sp-xxx "task"` to create with dependency
- `pm status` shows blocked spores differently

### 2. Docs Folder

Spores can have associated documents:
```
.plasmodium/
└── docs/
    └── sp-abc/
        ├── plan.md           # design document
        └── reviews/
            └── maple.md      # reviewer feedback
```

Spore gets `plan_file` field pointing to its plan doc.

### 3. Plan & Approval System

Before executing, workers must get their plan approved:

```bash
pm plan sp-xxx --approvals 2
# → Worker writes docs/sp-xxx/plan.md
# → Creates review spore sp-xxx-r1
# → sp-xxx status becomes "pending_approval"
```

Spore structure additions:
```json
{
  "approvals_needed": 2,
  "approvals": ["@maple"],
  "rejections": []
}
```

### 4. Review Spores

Reviews are spores themselves:
```json
{
  "id": "sp-abc-r1",
  "type": "review",
  "reviews": "sp-abc",
  "task": "review plan for sp-abc",
  "status": "raw"
}
```

Workers prioritize reviews (they unblock other workers).

### 5. Approve/Reject Commands

```bash
pm approve sp-xxx "looks good"
# → Adds worker to sp-xxx.approvals
# → Fruits the review spore
# → If approvals >= approvals_needed, unblocks sp-xxx

pm reject sp-xxx "needs changes because X"
# → Adds to sp-xxx.rejections
# → Worker must revise plan
```

### 6. Gates (Hooks)

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
