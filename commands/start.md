---
description: Start a new multi-agent relay with the team (CEO, PM, developers, designers)
---

# Start Team Relay

Start a multi-agent relay that runs in the background while you monitor progress.

## Arguments

Format: `[agent] [task description]`

- **agent** (optional): Starting agent - defaults to `ceo`
  - Options: ceo, pm, dev_john, dev_alice, designer_maya, designer_alex, qa_andrew
- **task**: The task for the team to complete

$ARGUMENTS

## Instructions

1. **Parse arguments**: Extract the starting agent and task from the arguments. If no agent specified, default to `ceo`.

2. **Find the orchestrator**: The orchestrator script is at the plugin directory. Look for it at:
   - `~/.claude/plugins/cache/local/team-relay/1.0.0/orchestrator.sh`
   - Or the directory this plugin was loaded from

3. **Reset and start the relay in background**:
   ```bash
   # Reset first
   /path/to/orchestrator.sh reset "$(pwd)"

   # Start in background, redirect output
   nohup /path/to/orchestrator.sh start "$(pwd)" <agent> "<task>" > /dev/null 2>&1 &
   ```

4. **Monitor the relay**: While the relay runs, periodically check the logs and summarize what's happening:
   ```bash
   # Check if relay is still running
   pgrep -f "orchestrator.sh start"

   # Read latest output
   tail -20 .team-relay/output.log

   # Read chat log for team communication
   cat .team-relay/chat.log
   ```

5. **Provide updates**: Every few seconds, read the output.log and chat.log and give the user a summary:
   - Which agent is currently working
   - What they're doing (from chat.log)
   - Any handoffs that occurred
   - When the relay completes (look for "RELAY COMPLETE" in output.log)

6. **On completion**: When the relay finishes:
   - Provide a summary of what was accomplished
   - List files created/modified
   - Show the full chat.log conversation

7. **Start the app**: If the project has a runnable app (web server, API, etc.):
   - Find an open port (check if 3000, 8080, 5000 are available)
   - Start the server in the background using the appropriate command:
     - Node: `npm start` or `node server.js`
     - Python: `python app.py` or `flask run`
     - Check package.json, Makefile, or README for start commands
   - Tell the user the URL (e.g., "App running at http://localhost:3000")
   - Run the console checker to verify no errors:
     ```bash
     node tools/check-console.js http://localhost:PORT
     ```
