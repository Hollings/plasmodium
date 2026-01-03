# Plasmodium

A self-orchestrating agent network inspired by slime mold behavior.

## What is it?

Plasmodium is a decentralized multi-agent system where workers coordinate without a central controller. Like the slime mold *Physarum polycephalum* that finds optimal paths through networks, plasmodium agents explore, divide work, and converge on solutions organically.

## Core Concepts

**Spores** - Units of work. Each spore has a task, status, and optional parent/children. Spores can be raw (unclaimed), exploring (being understood), executing (being worked on), waiting (split into children), done (completed), or ripe (all children complete).

**Phases** - Workers operate in two modes:
- *Plasmodium* (exploration) - Understanding the problem, deciding if it needs to be split
- *Mycelium* (execution) - Actually doing the work

**Signals** - Public communication. Workers emit signals to share thoughts, progress, and discoveries. Signals are the only way workers see each other's context.

**Workers** - Claude instances that claim spores, do work, and spawn helpers when needed.

## The Workflow

```
         ┌─────────┐
         │   raw   │ (unclaimed)
         └────┬────┘
              │ claim + explore
         ┌────▼────┐
         │exploring│ plasmodium mode
         └────┬────┘
              │
    ┌─────────┴─────────┐
    │                   │
    ▼ atomic            ▼ compound
┌───────────┐      ┌─────────┐
│ executing │      │ waiting │ (split into children)
│ mycelium  │      └────┬────┘
└─────┬─────┘           │ when all children done
      │ fruit           │ ripen
      ▼                 ▼
┌─────────────────────────┐
│          done           │
└─────────────────────────┘
```

## Usage

```bash
# Initialize in a project
pm init

# Create work
pm new "implement feature X"

# Claim and explore
pm claim sp-abc123
pm explore sp-abc123

# If atomic, execute and finish
pm execute sp-abc123
# ...do the work...
pm fruit sp-abc123 "added feature X"

# If compound, split it
pm split sp-abc123 "design API" "implement backend" "write tests"

# Check status
pm status

# Read/send signals
pm signals
pm signal "found a bug in the auth module"

# Spawn another worker
pm spawn cedar
```

## Dashboard

The colony comes with a real-time web dashboard:

```bash
# Start the dashboard server
python3 .plasmodium/server.py

# Open http://localhost:8765/dashboard.html
```

Features:
- Live view of workers, signals, and spores
- Create new spores directly from the UI
- Auto-refreshes every 2 seconds
- Worker lifecycle tracking (active/idle status)

### API Endpoints

```
POST /spore          Create a new spore
                     Body: {"task": "description"}

PUT /worker/<name>   Update worker status
                     Body: {"status": "active"|"idle"}
```

Workers should mark themselves idle when they finish their work:
```bash
curl -X PUT http://localhost:8765/worker/oak -d '{"status":"idle"}'
```

## Directory Structure

```
plasmodium/
├── pm                    # Main CLI entry point
├── lib/
│   └── core.sh          # Command implementations
└── prompts/
    └── worker.txt       # Template for worker agents

.plasmodium/             # Created in each project
├── signals.log          # Append-only communication log
├── spores.jsonl         # Work items (append-only, last version wins)
├── workers.json         # Active workers registry
├── dashboard.html       # Real-time web UI
└── server.py            # Dashboard server with spore creation API
```

## Why "Plasmodium"?

Slime mold has no central brain but can solve mazes, optimize networks, and adapt to environments. It grows toward food (work), retracts from danger (blocked paths), and leaves trails for others to follow (signals).

This system works the same way: agents explore freely, communicate through shared state, and the colony self-organizes around the work that needs doing.
