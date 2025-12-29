# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Claude Code plugin (`team-relay`) that provides a multi-agent orchestration system simulating a software development team. The orchestrator runs multiple Claude instances as different team members (CEO, PM, developers, designers, QA) who communicate via a shared chat log and hand off work to each other.

## Plugin Usage

Load the plugin with:
```bash
claude --plugin-dir /path/to/this/plugin
```

Or add an alias to ~/.zshrc:
```bash
alias claude='claude --plugin-dir /path/to/this/plugin'
```

### Slash Commands

| Command | Description |
|---------|-------------|
| `/team-relay:start [agent] <task>` | Start a new relay (agent defaults to ceo) |
| `/team-relay:continue <agent>` | Continue an interrupted relay |
| `/team-relay:reset` | Reset all state (chat log, sessions) |
| `/team-relay:status` | Show current relay status |

### Examples
```
/team-relay:start Build a todo app with dark mode
/team-relay:start ceo Build a todo app with dark mode
/team-relay:start pm Add user authentication
/team-relay:continue dev_john
/team-relay:status
```

## Direct CLI Usage

Run the orchestrator directly:

```bash
# Start a new relay
./orchestrator.sh start /path/to/project ceo "Build a todo app"

# Continue an interrupted relay
./orchestrator.sh continue /path/to/project dev_john

# Reset workspace
./orchestrator.sh reset /path/to/project
```

## Architecture

**Agent relay pattern**: Each agent runs one turn, reads `chat.log` for context, does work, logs their output, and outputs `NEXT: <agent>` or `DONE`. The orchestrator parses this and runs the next agent.

**Workspace**: Created in the target project as `.team-relay/`:
- `chat.log` - Team communication (append-only)
- `output.log` - Orchestrator activity log
- `sessions.json` - Session IDs for resuming
- `debug.log` - Detailed debug output

**Team roles**:
| Agent | Model | Role |
|-------|-------|------|
| ceo | sonnet | Vision/direction, delegates to PM |
| pm | sonnet | Coordination, task breakdown, assigns to pairs |
| dev_john | opus | Developer, pairs with dev_alice |
| dev_alice | opus | Developer, pairs with dev_john |
| designer_maya | opus | Senior designer - UX, usability, mentorship |
| designer_alex | haiku | Junior designer - fresh ideas, creativity |
| qa_andrew | opus | QA - testing, verification, cleanup, docs |

**Communication**: Agents communicate ONLY via `chat.log`. They read it at start of turn and write to it before handing off.

## Key Files

**Plugin structure:**
- `.claude-plugin/plugin.json` - Plugin manifest
- `commands/*.md` - Slash command definitions
- `orchestrator.sh` - Main orchestrator script
- `agent-prompts/*.txt` - Role-specific prompts

## Technical Constraints

When agents build web apps, all JS/CSS must be inlined into HTML to avoid CORS issues when opening locally (no external modules).
