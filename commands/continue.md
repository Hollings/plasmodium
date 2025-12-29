---
description: Continue an interrupted multi-agent relay from where it left off
---

# Continue Team Relay

Continue a multi-agent relay that was interrupted. This resumes from the last known state using saved sessions.

## Arguments

The user should provide: `<agent>`

- **agent**: Which team member should continue (ceo, pm, dev_john, dev_alice, designer_maya, designer_alex)

$ARGUMENTS

## Instructions

1. First, show the current state by displaying the last 10 lines of the chat log:

```bash
tail -10 ./agents-workspace/chat.log
```

2. Run the orchestrator in continue mode:

```bash
./agents-workspace/orchestrator.sh continue $ARGUMENTS
```

If working on a specific project:

```bash
./agents-workspace/orchestrator.sh --project /path/to/project continue <agent>
```

## Example Usage

- `/team-relay:continue dev_john`
- `/team-relay:continue pm`
