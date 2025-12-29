---
description: Show the current status of the team relay (chat log and sessions)
---

# Team Relay Status

View the current state of the multi-agent relay including the communication log and active sessions.

## Instructions

1. Show the full chat log:

```bash
cat ./agents-workspace/chat.log
```

2. Show which agents have active sessions:

```bash
cat ./agents-workspace/.sessions.json
```

3. Summarize:
   - How many messages are in the chat log
   - Which agents have been active
   - What the last handoff was (if any)
   - Whether there's work in progress or if the relay is complete
