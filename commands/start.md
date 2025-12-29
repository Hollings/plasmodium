---
description: Start a new multi-agent relay with the team (CEO, PM, developers, designers)
---

# Start Team Relay

Start a new multi-agent relay using the orchestrator script. The relay simulates a software development team where agents hand off work to each other.

## Arguments

The user should provide: `<agent> <task>`

- **agent**: Which team member starts (ceo, pm, dev_john, dev_alice, designer_maya, designer_alex)
- **task**: The task description for the team

$ARGUMENTS

## Instructions

1. Parse the arguments to extract the starting agent and task
2. Run the orchestrator script to start the relay:

```bash
./agents-workspace/orchestrator.sh $ARGUMENTS
```

If the user wants to work on a specific project directory, they can use `--project <dir>`:

```bash
./agents-workspace/orchestrator.sh --project /path/to/project <agent> <task>
```

## Available Agents

| Agent | Role | Model |
|-------|------|-------|
| ceo | Vision, direction, delegates to PM | sonnet |
| pm | Coordination, task breakdown | sonnet |
| dev_john | Developer, pairs with dev_alice | opus |
| dev_alice | Developer, pairs with dev_john | opus |
| designer_maya | Designer, pairs with designer_alex | sonnet |
| designer_alex | Designer, pairs with designer_maya | sonnet |

## Example Usage

- `/team-relay:start ceo Build a todo app with dark mode`
- `/team-relay:start --project ~/my-app pm Add user authentication`
