# Claude Team Relay Plugin

A Claude Code plugin that simulates a software development team using multiple AI agents. Each agent has a specific role (CEO, PM, developers, designers, QA) and they collaborate by passing work to each other through a shared communication log.

## Why?

When Claude works alone on complex projects, it can lose focus, skip steps, or miss edge cases. This plugin addresses that by:

- **Forcing collaboration**: Agents must hand off work and review each other's output
- **Adding accountability**: QA verifies against a deliverables checklist before completion
- **Creating structure**: PM breaks down tasks, devs pair-program, designers iterate
- **Catching errors**: Headless browser testing catches console errors humans might miss

The result is more thorough, well-tested code with better documentation.

## Installation

### Option 1: Install from GitHub (recommended)

```bash
# Add the marketplace
/plugin marketplace add https://github.com/Hollings/claude-team-relay-plugin

# Install the plugin (choose user/project/local scope when prompted)
/plugin install team-relay@team-relay-marketplace
```

### Option 2: Install from local clone

```bash
# Clone the repo
git clone git@github.com:Hollings/claude-team-relay-plugin.git

# Add as local marketplace
/plugin marketplace add ./claude-team-relay-plugin

# Install
/plugin install team-relay@team-relay-marketplace
```

### Option 3: Development mode (temporary, current session only)

```bash
claude --plugin-dir ./claude-team-relay-plugin
```

## Usage

### Start a new relay

```
/team-relay:start Build a todo app with dark mode
/team-relay:start ceo Build a REST API for user authentication
/team-relay:start pm Add search functionality to the dashboard
```

The relay runs in the background while Claude monitors progress and provides detailed updates on what the team is doing.

### Other commands

| Command | Description |
|---------|-------------|
| `/team-relay:start [agent] <task>` | Start a new relay (defaults to CEO) |
| `/team-relay:continue <agent>` | Resume an interrupted relay |
| `/team-relay:reset` | Clear all relay state |
| `/team-relay:status` | Show current relay status |

## The Team

| Agent | Model | Role |
|-------|-------|------|
| **CEO** | Sonnet | Sets vision and direction, delegates to PM |
| **PM** | Sonnet | Creates deliverables doc, breaks down tasks, coordinates team |
| **DEV_JOHN** | Opus | Developer - writes code, pairs with Alice |
| **DEV_ALICE** | Opus | Developer - reviews John's code, writes code |
| **DESIGNER_MAYA** | Opus | Senior designer - UX expertise, mentors Alex |
| **DESIGNER_ALEX** | Haiku | Junior designer - fresh ideas, creative energy |
| **QA_ANDREW** | Opus | Final gatekeeper - testing, verification, cleanup, docs |

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                     USER TASK                           │
└─────────────────────┬───────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────┐
│  CEO: Interprets task, sets vision, delegates to PM    │
└─────────────────────┬───────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────┐
│  PM: Creates DELIVERABLES.md, assigns work to pairs    │
└──────────┬──────────────────────────────┬───────────────┘
           │                              │
           ▼                              ▼
┌──────────────────────┐      ┌───────────────────────────┐
│  DEV_JOHN ↔ ALICE    │      │  DESIGNER_MAYA ↔ ALEX     │
│  Code, review, iterate│      │  Design, debate, agree    │
└──────────┬───────────┘      └───────────┬───────────────┘
           │                              │
           └──────────┬───────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────┐
│  QA_ANDREW: Verify deliverables, test, cleanup, docs   │
│  → If issues found, send back to appropriate agent     │
│  → If 100% complete, finish relay                      │
└─────────────────────┬───────────────────────────────────┘
                      ▼
                    DONE
        (Claude starts the app and verifies it works)
```

### The Deliverables Contract

PM creates `.team-relay/DELIVERABLES.md` at the start:

```markdown
# Project Deliverables

## Summary
Building a todo app with dark mode support...

## Features
- [ ] Add/edit/delete todo items
- [ ] Mark todos as complete
- [ ] Dark mode toggle
- [ ] Persist to localStorage

## Ready Checklist
- [ ] All features implemented
- [ ] No console errors
- [ ] Tests pass
- [ ] README exists
```

QA verifies 100% of checkboxes before approving. If anything fails, work goes back to the responsible agent.

### Communication

Agents communicate through `.team-relay/chat.log`:

```
[CEO] Task received: Build a todo app with dark mode. This should be a simple
single-page app that stores todos in localStorage...

[PM] Breaking this into phases:
1. Design - Maya will create wireframes
2. Implementation - John will build the core functionality
3. QA - Andrew will verify everything works

[DESIGNER_MAYA] Starting with mobile-first layout. Proposing a simple list view
with a floating action button for adding todos...

[DESIGNER_ALEX] I like it but what about swipe-to-delete? More intuitive than
a delete button...
```

## Workspace Structure

The relay creates a `.team-relay/` directory in your project:

```
your-project/
└── .team-relay/
    ├── chat.log           # Team communication (append-only)
    ├── output.log         # Orchestrator activity
    ├── sessions.json      # Session IDs for resuming
    ├── DELIVERABLES.md    # Contract created by PM
    └── tools/
        └── check-console.js  # Headless browser testing
```

## Features

### Automatic Service Startup

When the relay completes, Claude automatically:
- Detects your stack (Docker, Node, Python, etc.)
- Starts the appropriate services
- Verifies no console errors with headless Chrome
- Reports the URL when ready

### Headless Console Checking

QA uses Puppeteer to catch JavaScript errors:

```bash
node .team-relay/tools/check-console.js http://localhost:3000
```

Returns JSON with all console errors, warnings, and failed network requests.

### Detailed Progress Updates

While the relay runs, Claude provides specific updates:

> Maya is designing a dark header with centered logo and hamburger menu.
> Alex pushed back saying hamburgers are outdated - they're debating a
> bottom tab bar instead.

Not vague summaries like "Maya is working on the design."

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- Node.js (for console checker)
- Puppeteer (`npm install puppeteer` - installed automatically when needed)

## License

MIT
