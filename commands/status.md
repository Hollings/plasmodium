---
description: Show the current status of the team relay (chat log and sessions)
---

# Team Relay Status

Show the current state of any running or completed relay.

## Instructions

1. **Check if relay is running**:
   ```bash
   pgrep -f "orchestrator.sh"
   ```

2. **Show the workspace state**:
   ```bash
   # Output log (orchestrator activity)
   cat .team-relay/output.log 2>/dev/null || echo "No output log"

   # Chat log (team communication)
   cat .team-relay/chat.log 2>/dev/null || echo "No chat log"

   # Active sessions
   cat .team-relay/sessions.json 2>/dev/null || echo "No sessions"
   ```

3. **Summarize**:
   - Is a relay currently running?
   - How many turns have occurred?
   - Which agents have participated?
   - What's the current state (in progress, complete, or no relay)?
