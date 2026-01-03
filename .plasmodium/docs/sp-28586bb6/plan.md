# Plan for sp-28586bb6

## Task
Test auto-spawn feature

## Approach
The auto-spawn feature has two trigger points in core.sh:
1. **Line 210-213**: When `@human` creates a non-blocked spore, `spawn_workers_background 1` is called
2. **Line 712-713**: When `pm plan` is submitted with `--approvals N`, `spawn_workers_background N` is called

Since I (@beech_51e3) was spawned when this spore was created, **path 1 is already confirmed working**.
The human created sp-28586bb6, and I exist - that's proof.

For path 2 (plan approval spawning), I'll verify by:
1. Checking if submitting this plan spawns a new worker
2. Observing the workers.json file before/after

## Changes
No code changes needed - this is a testing/verification task.

## Risks
- Workers spawned in background may take time to start
- If claude CLI isn't available or permissions fail, spawn will fail silently

## Testing
1. Check current worker count in workers.json
2. Submit this plan with --approvals 1
3. Check workers.json again - should see a new worker
4. Check signals.log for "spawning worker @..." message
5. Check logs directory for new worker log file
