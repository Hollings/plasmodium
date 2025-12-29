---
description: Reset all team relay state (chat log, sessions, debug log)
---

# Reset Team Relay

Clear all relay state to start fresh.

## Instructions

1. **Find the orchestrator**: Look for it at:
   - `~/.claude/plugins/cache/local/team-relay/1.0.0/orchestrator.sh`
   - Or the directory this plugin was loaded from

2. **Reset the workspace**:
   ```bash
   /path/to/orchestrator.sh reset "$(pwd)"
   ```

3. **Confirm**: Tell the user the relay state has been cleared and they can start fresh with `/team-relay:start`.
