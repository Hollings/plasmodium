# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Claude Code plugin (`team-relay`) that provides a multi-agent orchestration system simulating a software development team. The orchestrator runs multiple Claude instances as different team members (CEO, PM, developers, designers) who communicate via a shared chat log and hand off work to each other.

## Plugin Usage

Load the plugin with:
```bash
claude --plugin-dir /path/to/this/plugin
```

### Slash Commands

| Command | Description |
|---------|-------------|
| `/team-relay:start <agent> <task>` | Start a new relay with the specified agent and task |
| `/team-relay:continue <agent>` | Continue an interrupted relay |
| `/team-relay:reset` | Reset all state (chat log, sessions) |
| `/team-relay:status` | Show current relay status |

### Examples
```
/team-relay:start ceo Build a todo app with dark mode
/team-relay:start --project ~/my-app pm Add user authentication
/team-relay:continue dev_john
/team-relay:status
```

## Direct CLI Usage

You can also run the orchestrator directly:

### Start a new relay
```bash
./agents-workspace/orchestrator.sh [--project <dir>] [--no-reset] <agent> <task>
```

### Continue an interrupted relay
```bash
./agents-workspace/orchestrator.sh [--project <dir>] continue <agent>
```

### Reset all state
The orchestrator resets by default on new runs. Use `--no-reset` to preserve state.

## Architecture

**Agent relay pattern**: Each agent runs one turn, reads `chat.log` for context, does work, logs their output, and outputs `NEXT: <agent>` or `DONE`. The orchestrator parses this and runs the next agent.

**Prompts structure**:
- `agent-prompts/_base.txt` - Common instructions injected into all agents (read chat.log first, log before handoff, valid agent names)
- `agent-prompts/<agent>.txt` - Role-specific instructions

**Team roles**:
- `ceo` - Vision/direction, delegates to PM (sonnet)
- `pm` - Coordination, task breakdown, assigns to pairs (sonnet)
- `dev_john`, `dev_alice` - Developer pair, review each other's code (opus)
- `designer_maya`, `designer_alex` - Designer pair, iterate on designs until both agree (sonnet)

**Session persistence**: Agent sessions are stored in `.sessions.json` so conversations can be resumed with `--resume`.

**Communication**: Agents communicate ONLY via `chat.log` (append-only). They must read it at start of turn and write to it before handing off.

## Key Files

**Plugin structure:**
- `.claude-plugin/plugin.json` - Plugin manifest
- `commands/*.md` - Slash command definitions

**Orchestrator:**
- `agents-workspace/orchestrator.sh` - Main orchestrator script
- `agents-workspace/chat.log` - Shared communication log (append-only)
- `agents-workspace/.sessions.json` - Session IDs for resuming conversations
- `agents-workspace/debug.log` - Debug output from orchestrator

**Agent prompts:**
- `agent-prompts/_base.txt` - Common instructions for all agents
- `agent-prompts/<agent>.txt` - Role-specific prompts

## Technical Constraints

When agents build web apps, all JS/CSS must be inlined into HTML to avoid CORS issues when opening locally (no external modules).
