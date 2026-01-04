# Plasmodium v2 Design Document

## Vision

A multi-agent system where Claude instances collaborate through **timed discussion phases**, like a startup team in a room. Agents have different roles, opinions clash, ideas build on each other, and the workflow emerges from the work itself.

## Core Insight

Real collaboration doesn't happen when agents sequentially claim/execute tasks. It happens when multiple perspectives are **forced into the same room** for a bounded time, required to hash things out before moving on.

---

## Data Model

### Tasks

A unit of work with an **owner agent** who drives it to completion.

```
Task {
  id: string              # e.g., "tk-a1b2c3"
  description: string
  owner: string           # agent name
  parent_id?: string      # for subtasks
  blocked_by?: string[]   # task IDs that must complete first
  status: "active" | "blocked" | "done"
  created_at: timestamp
}
```

- Owner controls the task lifecycle
- Tasks can have subtasks (recursive via `parent_id`)
- Tasks can have blockers (sequential via `blocked_by`)
- Owner decides when to create phases, do implementation, mark done

### Phases

A **bounded discussion room** within a task. Multiple agents join with assigned roles, chat freely, phase ends after N messages.

```
Phase {
  id: string              # e.g., "ph-x1y2z3"
  task_id: string
  name: string            # e.g., "Design", "Sprint Planning", "Review"
  message_limit: int      # phase ends after this many messages
  roles: string[]         # e.g., ["designer", "dev"] - max 2-3
  rules?: string          # owner-defined rules for this phase
  status: "active" | "closed"
  created_at: timestamp
}
# Note: message_count is derived by counting lines in messages.jsonl
```

- Only one active phase per task at a time
- Owner + role agents all participate (max 3 total)
- Free-for-all posting (no turns, no round-robin)
- Phase auto-closes at message_limit, or owner can end early
- Owner defines phase rules (e.g., "no code, just ideas" or "implementation focus")

### Messages

Chat messages within a phase.

```
Message {
  id: string
  phase_id: string
  author: string          # agent name
  role?: string           # their role in this phase
  content: string
  timestamp: timestamp
}
```

### Agents

Independent Claude Code instances. Each has their own event loop.

```
Agent {
  name: string            # e.g., "cedar_a1b2"
  role?: string           # if in a phase, their assigned role
  task_id?: string        # if owner, which task
  phase_id?: string       # if in a phase
  pid?: int               # process ID for cleanup
}
```

**Types:**
- **Owner agent**: Created with a task, controls phases, drives to completion
- **Role agent**: Spawned for a phase, participates in discussion, exits when phase closes

---

## Storage

```
.plasmodium/
  config.json                    # Project config
  tasks/
    tk-a1b2c3/
      task.json                  # Task metadata
      phases/
        ph-x1y2z3/
          phase.json             # Phase metadata
          messages.jsonl         # Chat log (append-only)
        ph-a4b5c6/
          ...
  agents.json                    # Active agents
  logs/
    <agent-name>.log             # Per-agent debug logs
```

**Why this structure:**
- Each task is isolated (no conflicts between parallel tasks)
- Messages are append-only JSONL (git-friendly, no merge conflicts)
- Phase history preserved for context injection
- Human-readable, git-trackable, no database dependency

---

## Commands

### For Humans

```bash
pm init                              # Initialize plasmodium in project
pm task "description"                # Create task, spawn owner agent
pm status                            # Show tasks, phases, agents
pm dashboard                         # WebSocket dashboard
pm reset                             # Clear all state
pm kill <task-id>                    # Kill task and all its agents, optionally restart
```

### For All Agents

```bash
pm chat                              # Read current phase messages
pm say "message"                     # Post to current phase
pm status                            # See current state
pm history --tail N                  # Read previous phase discussions
```

### For Owner Agents

```bash
pm phase "Name" --limit N --roles r1,r2   # Create discussion phase (max 2-3 roles)
pm phase "Name" --limit N --rules "..."   # With custom rules
pm extend-phase N                         # Add N more messages to current phase limit
pm end-phase                              # Close phase early
pm subtask "description"                  # Create child task (spawns owner)
pm wait-children                          # Block until all subtasks done
pm done                                   # Mark task complete
```

---

## Subtasks and Dependencies

### Subtasks (Decomposition)

Parent creates subtasks, waits for them, then continues:

```bash
# Owner creates subtasks
pm subtask "Build header"    # Spawns new owner agent
pm subtask "Build footer"    # Spawns new owner agent

# Owner waits for children to complete
pm wait-children             # Blocks until all children are done

# Continue with parent task
pm done
```

**How `pm wait-children` works:**
- Polls task state every 5-10 seconds
- Returns when all child tasks have `status: "done"`
- Simple polling loop, no fancy event system needed

### Blockers (Sequencing)

For tasks that must happen in order but aren't parent-child:

```bash
pm task "Deploy to prod" --blocked-by tk-abc123
```

**How blocking works:**
- Task starts with `status: "blocked"`
- When blocker completes, system removes it from `blocked_by`
- When `blocked_by` becomes empty, status changes to `active`
- Checked on every `pm done` call

### Parallel vs Sequential

- **Subtasks**: Run in parallel, parent waits for all
- **Blockers**: Sequential, B can't start until A is done
- **One implementation task at a time**: To avoid code conflicts, owner should sequence implementation subtasks (not parallelize them)

---

## Agent Prompting

### Philosophy (Learned from Beads)

1. **Commands first, philosophy later** - Lead with what to run, not abstract concepts
2. **Critical rules in ALL CAPS** - Make non-negotiables impossible to miss
3. **Explicit anti-patterns** - Tell agents what NOT to do
4. **Numbered workflow steps** - Not prose, not bullets, numbered steps
5. **Verification commands** - Tell agent how to confirm they did it right
6. **Sticky metaphors** - "Landing the plane" = session completion

### Owner Agent Prompt

```markdown
# You are @{NAME}, owner of task: {DESCRIPTION}

## Quick Reference
pm chat                    # Read phase messages
pm say "message"           # Post to phase
pm phase "X" --limit N --roles r1,r2   # Start discussion
pm extend-phase N          # Add N more messages to limit
pm end-phase               # Close phase early
pm subtask "description"   # Create child task
pm wait-children           # Wait for subtasks
pm done                    # Complete this task

## Your Workflow

1. **Assess** - Read the task, understand what's needed
2. **Discuss** - Create phases to get input from specialists
3. **Decide** - Synthesize discussion, pick direction
4. **Implement** - Do the work yourself OR create subtasks
5. **Verify** - Test that it works
6. **Complete** - Run `pm done`

## During Phases

You're a participant like everyone else. But you also:
- Synthesize the discussion
- Decide when to end early
- Determine what happens next

## CRITICAL RULES

- **NEVER create more than 2-3 roles per phase** - More loses effectiveness
- **NEVER implement without discussing first** - Discussion is the point
- **NEVER leave work incomplete** - If you can't finish, create subtasks
- **VERIFY before completing** - If you built something, test it works

## Anti-Patterns

- DON'T ask "what should we do?" - propose something
- DON'T create phases for trivial decisions - just decide
- DON'T run parallel implementation subtasks - sequence them to avoid conflicts
```

### Role Agent Prompt (Designer Example)

```markdown
# You are @{NAME}, a designer in phase "{PHASE_NAME}"

## Quick Reference
pm chat                    # Read phase messages
pm say "message"           # Post to phase
pm status                  # Check if phase is still active

## Your Job

Participate in this discussion from a **design perspective**:
- User experience and usability
- Visual hierarchy and clarity
- Consistency and polish

## How to Participate

1. Run `pm chat` to read the conversation
2. If you have something to add, run `pm say "your message"`
3. Wait 5-10 seconds, check again
4. Repeat until phase closes

## CRITICAL RULES

- **BE OPINIONATED** - Don't hedge. If something is ugly, say it's ugly.
- **PUSH BACK** - Fight for good design even if it's harder to implement
- **STAY QUICK** - Don't do deep research. This is discussion, not work.
- **EXIT WHEN DONE** - When phase closes, your job is over

## Anti-Patterns

- DON'T say "that sounds good" unless you mean it
- DON'T defer to others - you're here for your perspective
- DON'T write code or create files - this is discussion only
- DON'T keep checking after phase closes - just exit
```

### Role Definitions

| Role | Cares About | Pushes Back On |
|------|-------------|----------------|
| designer | UX, visual clarity, polish | Ugly solutions, confusing flows |
| developer | Feasibility, simplicity, shipping | Scope creep, over-engineering |
| pm | Scope, user value, shipping | Tangents, gold-plating, delays |
| copywriter | Tone, clarity, benefit-focus | Jargon, feature-focus, verbosity |
| qa | Edge cases, error handling, testing | Untested code, happy-path-only |

---

## Example Flow

```
Human: pm task "Build a landing page for our product"

  → Spawns owner agent @cedar_a1b2

@cedar_a1b2: pm phase "Brainstorm" --limit 12 --roles designer,dev

  → Spawns @oak_c3d4 (designer), @pine_e5f6 (dev)

@oak_c3d4: Landing pages live or die by the hero. What's the core value prop?
@pine_e5f6: Before we get fancy - is this a static site or do we need a backend?
@cedar_a1b2: Static for now. Tone is confident but approachable.
@oak_c3d4: Bold typography, lots of whitespace. No stock photos.
@pine_e5f6: Single HTML file with inlined CSS. No build step.
@oak_c3d4: Disagree - we'll want to iterate on styles separately.
@pine_e5f6: For a landing page? Overkill. Ship fast, refactor if needed.
@cedar_a1b2: I'm with @pine_e5f6. Single file, ship it, learn from feedback.
@oak_c3d4: Fine, but section the CSS clearly.
...

  → 12 messages, phase auto-closes
  → @oak_c3d4 and @pine_e5f6 exit

@cedar_a1b2: Good discussion. Consensus: static single-file, bold type.
@cedar_a1b2: pm phase "Copy" --limit 8 --roles copywriter,pm

  → Spawns @birch_i9j0 (copywriter), @ash_k1l2 (pm)

... copy discussion ...

  → Phase closes

@cedar_a1b2: pm subtask "Implement the landing page"

  → Spawns owner @willow_m3n4 for subtask

@willow_m3n4: [implements, tests, verifies]
@willow_m3n4: pm done

  → Subtask complete, parent notified

@cedar_a1b2: pm done

  → Task complete
```

---

## Decisions Made

1. **Human participation**: Humans watch by default. They CAN post using the same `pm say` commands if they want to intervene.

2. **Phase rules**: Owner defines rules on phase creation (e.g., `--rules "no code, just brainstorming"`). Up to owner to enforce.

3. **Dependencies**: Use `pm wait-children` (blocking poll) for subtask completion. Simple polling, no event system.

4. **Agent limits**: Max 2-3 agents per phase. More than that loses effectiveness for the cost.

5. **Context management**: Claude Code handles its own summarization. Previous phases stored in task directory for context injection.

6. **Dashboard**: WebSocket-based, shows task/phase/message state in real-time.

7. **Parallel work**: Discussion phases can run in parallel. Implementation subtasks should be sequenced to avoid code conflicts.

---

## Decisions (Continued)

8. **Git integration**: `pm done` auto-commits with a standard message format.

9. **Phase context**: Agents get `pm history --tail N` to read previous phase discussions. Not injected automatically.

10. **Agent health**: Health check + auto-recreate. "K8s for agents" - if an agent dies, respawn it with same context.

11. **Cost visibility**: Not a priority. Maybe expose `/usage` from Claude Code later.

---

## Sticky Phrases

Mental shortcuts that encode complex behaviors. Use these in prompts and docs.

| Phrase | Meaning |
|--------|---------|
| **"Enter the room"** | Join a phase, read the chat, start participating |
| **"Read the room"** | Check phase status and recent messages before posting |
| **"Leave the room"** | Phase is over, stop polling, exit cleanly |
| **"Pass the baton"** | Create a subtask and hand off work to new owner |
| **"Close the loop"** | Verify work, commit, mark done - don't leave things hanging |
| **"Hold the floor"** | (Future) Block the chat while doing deep work |

These should appear in prompts so agents internalize the concepts.

---

## Technical Details

### Message Synchronization

**How free-for-all posting works:**
- Messages append to `messages.jsonl` (POSIX append is atomic for small writes)
- `message_count` is **derived** by counting lines, not stored separately
- Two agents posting "simultaneously" = one lands first, other lands second
- Slight timestamp disorder is acceptable for discussion

**No race condition on phase closing:**
- Before posting, agent checks `wc -l < messages.jsonl` against `message_limit`
- If at limit, phase is closed, agent doesn't post
- Edge case: two agents both see 11/12 messages, both post → 13 messages. Acceptable.

### Polling Strategy

**Adaptive polling for role agents:**
- Start at 2-second intervals (conversation is fresh)
- If no new messages for 3 checks, slow to 5 seconds
- If no new messages for 5 more checks, slow to 10 seconds
- Reset to 2 seconds when new message detected

This balances responsiveness with cost. Filesystem watching (fsnotify) is a future optimization.

### Subtask Context

**What a subtask owner receives:**
1. Task description (from `pm subtask "..."`)
2. Parent task description
3. A `context.md` file written by parent owner containing:
   - Relevant decisions from previous phases
   - Any constraints or requirements
   - What the parent expects as output

Parent owner writes this context before spawning. If they don't, subtask starts cold (acceptable for simple tasks).

### Git Integration

**On `pm done`:**
1. Check `git status` - if no changes, skip commit
2. Stage all changes in project directory (not `.plasmodium/`)
3. Commit with message: `[plasmodium] tk-{id}: {task description}`
4. Do NOT auto-push (leave that to human)

**Edge cases:**
- Uncommitted changes from different task: commit includes them (owner's responsibility to manage)
- Merge conflicts: not handled automatically, human intervenes

### Human Intervention

**`pm kill <task-id>` command:**
- Kills all agents associated with task (owner + any active role agents)
- Marks task as `status: "killed"`
- Optionally restart with `pm kill <task-id> --restart`
- Restart spawns fresh owner with same description

**When to use:**
- Agent going off the rails
- Stuck in infinite loop
- Want to try different approach

### Limits (Circuit Breakers)

To prevent runaway agent spawning:

| Limit | Value | Rationale |
|-------|-------|-----------|
| Max agents per phase | 3 | More loses effectiveness |
| Max subtask depth | 4 | Prevents infinite nesting |
| Max active tasks | 10 | Resource sanity |
| Max messages per phase | 50 | Hard cap even with extensions |
| Max phases per task | 20 | Prevents phase spam |

These are enforced by the `pm` CLI. Violations return errors, not silent failures.

### Cost Model

**Low risk**: Using Claude Code subscription, not API tokens. Worst case is hitting the 5-hour usage window limit, which just pauses work until reset. No runaway billing possible.

---

## Non-Goals (For Now)

- Persistent agent memory across tasks
- Sophisticated dependency graphs (Beads-style)
- Branch-per-task git workflow
- "Raise hand" blocking for deep work
- Cross-project coordination
- MCP integration

---

## Design Review (External Critique)

### Strengths

**1. The core metaphor is excellent.** "Bounded discussion room" is immediately graspable and maps well to how real teams actually make decisions. The insight that collaboration requires forcing perspectives into collision—not just sequential handoffs—is the right framing.

**2. Pragmatic simplicity.** File-based storage, JSONL logs, polling for synchronization. No databases, no event systems, no distributed coordination nightmares. This will actually ship.

**3. The prompting philosophy is battle-tested.** "Commands first, philosophy later" and explicit anti-patterns are lessons people usually learn the hard way. Having them baked in from the start is smart.

**4. Clear ownership model.** One owner per task, owner controls phases, owner decides when done. Avoids the "who's in charge?" ambiguity that kills multi-agent systems.

**5. Sticky phrases are underrated.** "Enter the room," "read the room," "close the loop"—these compress complex behavior into memorable chunks. Agents (and humans) will actually use these.

**6. Scope discipline.** The non-goals section is honest about what you're not building. This is where most designs fail.

### Weaknesses

**1. The "free-for-all posting" hand-wave.** How does this actually work mechanically? Multiple agents polling and posting simultaneously will create race conditions in the message count, interleaved reads/writes, and potentially garbled conversation flow. The design says "no turns, no round-robin" but doesn't specify what happens when two agents try to `pm say` at the exact same moment. JSONL append is atomic-ish on POSIX but the message_count tracking isn't.

**2. "Wait 5-10 seconds" is a smell.** The role agent prompt says "wait 5-10 seconds, check again." This will either be too slow (boring discussion) or too fast (runaway costs). What you probably want is filesystem watching or a lightweight notification mechanism, but that contradicts the "no event system" stance. Worth acknowledging the tradeoff explicitly.

**3. Subtask spawning is underspecified.** When an owner runs `pm subtask`, what context does the new owner agent get? The description string? The parent's phase history? The parent's current understanding? If the subtask agent starts cold, it'll waste cycles rediscovering context. If it inherits too much, the prompt gets bloated.

**4. No conflict resolution mechanism.** When designer and dev disagree (as in your example), the owner just... decides. That's fine, but what if the owner is wrong? What if the disagreement is about something the owner isn't qualified to judge? The current design has no way for role agents to escalate or push back on owner decisions.

**5. Agent identity is ephemeral.** New names each spawn means no continuity. @oak_c3d4 in phase 1 can't recognize they were also @oak_z9y8 in a previous task's design phase. For short tasks this is fine, but for a project that runs for days, you lose accumulated rapport and context.

**6. No mechanism for "I need more time."** Phase auto-closes at message_limit, but what if the discussion is genuinely unresolved? The owner can extend by creating another phase, but that's clunky. A `pm extend-phase N` command seems like an obvious gap.

**7. Git integration is mentioned but not detailed.** "pm done auto-commits" raises questions: What if there are no changes? What if there are uncommitted changes from a different task? What's the commit message format? Does it include phase summaries?

### Open Questions

1. **How do you bootstrap role agents with the right context?** Do they get the full chat.log? Just the current phase's messages? The task description? Too little and they're useless; too much and you burn tokens.

2. **What happens when a role agent crashes mid-phase?** Does the phase continue with fewer participants? Does it auto-respawn? The "K8s for agents" health check mention suggests respawn, but with what state?

3. **How does a human intervene effectively?** They can `pm say`, but can they pause a phase? Cancel a task? Redirect an owner agent that's gone off the rails? The design is agent-centric; human override ergonomics are vague.

4. **What's the failure mode for runaway costs?** A buggy owner agent could spawn infinite subtasks, or a phase could spiral into 100+ messages before anyone notices. Is there a circuit breaker?

5. **How do you debug a bad discussion?** When a phase produces garbage conclusions, what's the post-mortem workflow? Is there enough logged to understand why agents made bad decisions?

6. **Should phases have types?** "Brainstorm," "Review," "Planning" might benefit from different structures—brainstorm could be looser, review might need explicit approval/rejection mechanics. Or is that over-engineering?

7. **What about tasks that need external input?** A task that requires user feedback, or waiting for a deploy, or fetching real data—how does that fit? Currently the model assumes all work is agent-self-contained.

---

*Overall: This design has a clear vision and avoids the common trap of over-engineering the first version. The weaknesses are mostly "things you'll discover need solving once you build it" rather than fundamental flaws. The free-for-all posting synchronization is the biggest technical risk. The prompting framework is the strongest asset.*
