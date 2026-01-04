# Plasmodium Status

## What It Is

Multi-agent collaboration system. Owner agent creates bounded discussion phases with perspectives, agents discuss and build, work items track parallel implementation.

## Current State (Working)

- `pm init` - initializes project, auto-starts dashboard
- `pm task "..."` - creates task, spawns owner agent
- `pm phase` - owner creates discussion phases with perspectives
- `pm chat/say` - agents communicate in phases
- `pm work/work-done` - work item tracking
- `pm dashboard/dashboard-stop` - web UI for monitoring
- Dashboard shows tasks, phases, messages, work items

## Recent Fixes

1. **pm init auto-starts dashboard** on available port
2. **pm task shows guidance** ("Monitor progress: pm status")
3. **Agent logs now have start/exit markers** for debugging
4. **pm dashboard-stop** kills dashboard by matching --pm-dir (safe with multiple)
5. **Agent prompt clarified** that `pm work` is a COMMAND not text format

## Issues Found (from bigyear test)

1. **Agents built standalone app instead of integrating** - Created new React app in `public/app/` instead of modifying existing `client/` React app. Root cause: no shared understanding of project structure.

2. **Agents wrote "[WORK]" in chat instead of running `pm work`** - Fixed in prompt, needs re-test.

3. **Agents may interrupt each other** - One researches, comes back, conversation moved on. Prompt now says "re-read chat before posting".

## Short-Term Goals

### 1. Explore Agent Before Owner (DONE)

**Problem**: Agents don't understand project structure. Each explores independently (wasteful) or not at all (builds wrong thing).

**Solution** (implemented):
- `pm task` kicks off Explore agent FIRST (runs in foreground)
- Explore agent writes `.plasmodium/tasks/tk-xxx/context.md`
- Context includes: project structure, frameworks, key files, conventions
- Owner spawns AFTER explore completes
- All phase agents get context injected at top of their prompts

**Files changed**:
- `prompts/explore.md` - New prompt for Explore agent
- `lib/core.sh` - `spawn_explore_agent()`, modified `pm_task()`, context injection in `spawn_agent_with_perspective()`

### 2. Re-test After Explore Feature (NEXT)

Run another test on bigyear to verify:
- Explore agent correctly identifies React app in `client/`
- Agents integrate with existing code instead of building standalone
- Work items are created via `pm work` command

### 3. Future Improvements (Not Now)

- Agents should be able to extend phases themselves (currently only owner)
- Better handling of agent crashes/timeouts
- Dashboard: show agent logs in UI
- Consider: agents review each other's work items before phase closes

## File Structure

```
/Users/john/the-project/
├── pm                    # CLI entry point
├── lib/core.sh           # All command implementations (~1300 lines)
├── dashboard/
│   ├── server.py         # Python HTTP server for API
│   └── index.html        # Single-page dashboard UI
├── prompts/
│   ├── explore.md        # Explore agent prompt (runs first)
│   ├── owner.md          # Owner agent prompt
│   └── agent.md          # Phase agent prompt (perspectives)
├── docs/
│   └── flowcharts.md     # Mermaid diagrams
└── README.md             # User-facing docs
```

## Key Concepts

- **Owner**: Facilitator only. Creates phases, defines perspectives, doesn't code.
- **Phase**: Bounded discussion (name + perspectives + message limit)
- **Perspective**: Freeform viewpoint assigned to agent (not fixed roles)
- **Work Items**: `pm work` to claim, `pm work-done` to complete. Phase won't close until all done.
- **Context**: (NEW) Project understanding written by Explore agent, shared with all agents.
