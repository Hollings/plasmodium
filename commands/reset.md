---
description: Reset all team relay state (chat log, sessions, debug log)
---

# Reset Team Relay

Clear all state from previous relays to start fresh.

## What Gets Reset

- `chat.log` - Clears all agent communication history
- `.sessions.json` - Clears saved session IDs (agents won't resume previous conversations)
- `debug.log` - Removes debug output

## Instructions

Reset all state by reinitializing the workspace files:

```bash
cd ./agents-workspace && \
echo '{}' > .sessions.json && \
echo "# Agent Communication Log
# APPEND ONLY - never edit previous entries
---" > chat.log && \
rm -f debug.log && \
echo "All state reset"
```

After resetting, confirm to the user that the relay state has been cleared and they can start a fresh relay with `/team-relay:start`.
