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

5. **Provide detailed updates**: Every few seconds, read the output.log and chat.log and narrate what's happening with SPECIFICS:

   **BAD** (too vague):
   - "Maya is working on the design"
   - "John is writing code"
   - "The team is making progress"

   **GOOD** (specific details):
   - "Maya is designing a dark header with a centered logo and hamburger menu on mobile. Alex pushed back saying the hamburger is outdated - they're debating a tab bar instead."
   - "John wrote a TodoItem component with checkbox, title, and delete button. Alice is reviewing and suggested adding keyboard shortcuts for accessibility."
   - "QA found 3 console errors: missing favicon, undefined localStorage on first load, and a React key warning in the todo list."

   Include:
   - Actual design decisions being discussed
   - Specific code/components being written
   - Real disagreements or debates between team members
   - Concrete bugs or issues found
   - File names and function names when relevant

6. **On completion**: When the relay finishes:
   - Provide a summary of what was accomplished
   - List files created/modified
   - Show the full chat.log conversation

7. **Start all services**: When the relay completes, get the app running - don't ask, just do it:

   **Docker/Compose** (check for docker-compose.yml or compose.yml):
   ```bash
   docker compose down 2>/dev/null; docker compose up -d --build
   ```

   **Node** (check for package.json):
   ```bash
   npm install && npm start &
   ```

   **Python** (check for requirements.txt, app.py, manage.py):
   ```bash
   pip install -r requirements.txt 2>/dev/null
   python app.py &  # or flask run, or python manage.py runserver
   ```

   **Makefile** (check for Makefile with 'run' or 'start' target):
   ```bash
   make run &  # or make start
   ```

   - Find an open port if needed (3000, 8080, 5000)
   - Wait for service to be healthy
   - Tell the user the URL when ready
   - Run console checker to verify:
     ```bash
     node .team-relay/tools/check-console.js http://localhost:PORT
     ```

   **If something fails**: Fix it or restart it. Don't tell the user to do it manually.
