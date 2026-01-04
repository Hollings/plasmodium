# Plasmodium

Multi-agent collaboration through bounded discussion phases.

## What is it?

Plasmodium coordinates multiple Claude instances to work on tasks together. An **owner** agent breaks work into **phases**, each with specific **perspectives** that debate and build. Phases have message limits that force convergence, and **work items** track parallel implementation.

## Quick Start

### 1. Install in your project

```bash
# From your project directory
/path/to/plasmodium/pm init
```

This creates a `.plasmodium/` directory and adds the `pm` command to your path for this session.

### 2. Start the dashboard

```bash
pm dashboard
# Opens http://localhost:3456
```

The dashboard shows tasks, phases, messages, and work items in real-time.

### 3. Create your first task

```bash
pm task "Build a REST API with health and time endpoints"
```

This spawns an **owner** agent who will:
1. Create a Design phase with 2+ perspectives (e.g., "minimalist", "pragmatist")
2. Let them debate until the message limit
3. Create a Build phase with implementer perspectives
4. Track work items until everything is complete

## Core Concepts

**Owner** - Coordinates the task. Creates phases, defines perspectives, synthesizes results. Doesn't implement—only orchestrates.

**Phase** - A bounded discussion with a name, perspectives, and message limit. Phases close when the limit is reached AND all work items are done.

**Perspective** - A viewpoint assigned to an agent (e.g., "security advocate", "UX minimalist", "test-first developer"). Not fixed roles—the owner defines what perspectives each phase needs.

**Work Items** - Claimed tasks within a phase. Agents call `pm work "description"` before building, `pm work-done "summary"` when finished. Prevents duplicate work and premature phase closure.

## Commands

### Project Setup
```bash
pm init                    # Initialize .plasmodium in current directory
pm dashboard [port]        # Start web dashboard (default: 3456)
pm reset                   # Clear all plasmodium state
```

### Task Management (for owners)
```bash
pm task "description"      # Create a new task (spawns owner agent)
pm status                  # Show all tasks and phases
```

### Phase Operations (for agents)
```bash
pm chat                    # Read current phase messages
pm say "message"           # Post to current phase
pm work "description"      # Claim a work item (announces to chat)
pm work-status             # See all work items in phase
pm work-done "summary"     # Mark your work complete
```

### Agent Management
```bash
pm spawn <name> [perspective]  # Spawn agent with perspective
pm register <name>             # Register current agent
pm kill <name>                 # Stop an agent
```

## Workflow Example

```
You: pm task "Add user authentication"

Owner creates phase: "Auth Design"
  Perspectives: security-advocate, ux-minimalist

  @security: "We need bcrypt, JWT tokens, rate limiting..."
  @ux: "Keep it simple - email/password, maybe OAuth later"
  @security: "At minimum: hashed passwords, secure sessions"
  @ux: "Agreed. Let's start with sessions, add JWT if needed"
  [Phase closed - 6/6 messages]

Owner creates phase: "Auth Build"
  Perspectives: backend-implementer, frontend-implementer

  @backend: "I'll handle the auth routes and middleware"
  @backend: [WORK] Starting: auth.py with login/logout/register
  @frontend: "I'll build the login form and session handling"
  @frontend: [WORK] Starting: login component and auth context
  @backend: [WORK DONE] auth.py complete with bcrypt + sessions
  @frontend: [WORK DONE] Login form with error handling
  [Phase closed - 8/8 messages, 2/2 work items done]

Owner: Task complete.
```

## Directory Structure

```
your-project/
├── .plasmodium/
│   ├── agents.json              # Registered agents
│   └── tasks/
│       └── tk-abc123/
│           ├── task.json        # Task metadata
│           └── phases/
│               └── ph-xyz789/
│                   ├── phase.json      # Phase config
│                   ├── messages.jsonl  # Chat log
│                   └── work.jsonl      # Work items

plasmodium/                      # The tool itself
├── pm                           # CLI entry point
├── lib/core.sh                  # Command implementations
├── dashboard/
│   ├── server.py               # Dashboard backend
│   └── index.html              # Dashboard frontend
└── prompts/
    ├── owner.md                # Owner agent prompt
    └── agent.md                # Phase agent prompt
```

## Why "Plasmodium"?

Like the slime mold *Physarum polycephalum*, this system has no central controller. Agents explore problems from different perspectives, communicate through shared state, and converge on solutions through bounded interaction. The owner provides structure, but the actual work emerges from collaboration.
