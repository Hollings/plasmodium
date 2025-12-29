---
description: Continue an interrupted multi-agent relay from where it left off
---

# Continue Team Relay

Resume a relay that was interrupted, starting with the specified agent.

## Arguments

Format: `<agent>`

- **agent**: Which agent should continue (ceo, pm, dev_john, dev_alice, designer_maya, designer_alex, qa_andrew)

$ARGUMENTS

## Instructions

1. **Check existing state**: Read `.team-relay/chat.log` to show the user what happened before the interruption.

2. **Find the orchestrator**: Look for it at:
   - `~/.claude/plugins/cache/local/team-relay/1.0.0/orchestrator.sh`
   - Or the directory this plugin was loaded from

3. **Continue the relay in background**:
   ```bash
   nohup /path/to/orchestrator.sh continue "$(pwd)" <agent> > /dev/null 2>&1 &
   ```

4. **Monitor and summarize**: Same as start - periodically read output.log and chat.log, provide updates to the user until the relay completes.
