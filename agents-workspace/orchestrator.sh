#!/bin/bash
# Multi-agent relay orchestrator
# Each agent gets one turn, outputs "NEXT: <agent>" or "DONE"

# Determine script location for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

ORCHESTRATOR_HOME="$SCRIPT_DIR"
PROMPTS_DIR="$PLUGIN_ROOT/agent-prompts"
CHAT_LOG="$ORCHESTRATOR_HOME/chat.log"
SESSIONS_FILE="$ORCHESTRATOR_HOME/.sessions.json"
DEBUG_LOG="$ORCHESTRATOR_HOME/debug.log"
MAX_TURNS=50

# Project directory (set via --project flag, defaults to orchestrator home)
PROJECT_DIR=""

# Initialize sessions file if needed
if [[ ! -f "$SESSIONS_FILE" ]]; then
    echo '{}' > "$SESSIONS_FILE"
fi

get_session() {
    local agent=$1
    jq -r ".[\"$agent\"] // empty" "$SESSIONS_FILE"
}

set_session() {
    local agent=$1
    local session_id=$2
    local tmp=$(mktemp)
    jq ".[\"$agent\"] = \"$session_id\"" "$SESSIONS_FILE" > "$tmp" && mv "$tmp" "$SESSIONS_FILE"
}

log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEBUG_LOG"
}

get_model() {
    local agent=$1
    case "$agent" in
        dev_john|dev_alice) echo "opus" ;;
        *) echo "sonnet" ;;
    esac
}

ensure_project_settings() {
    local work_dir=$1

    # Skip if running in orchestrator home (settings already there)
    if [[ "$work_dir" == "$ORCHESTRATOR_HOME" ]]; then
        return
    fi

    # Create .claude dir if needed
    mkdir -p "$work_dir/.claude"

    # Create settings with access to orchestrator home for chat.log
    cat > "$work_dir/.claude/settings.json" << EOF
{
  "permissions": {
    "additionalDirectories": ["$ORCHESTRATOR_HOME"],
    "allow": ["Bash", "Edit", "Read", "Write", "Glob", "Grep", "WebFetch", "WebSearch"],
    "deny": [
      "Read(~/.ssh/**)",
      "Read(~/.aws/**)",
      "Read(~/.config/**)",
      "Read(~/.claude/**)",
      "Read(/etc/**)",
      "Edit(~/.ssh/**)",
      "Edit(~/.aws/**)",
      "Edit(~/.config/**)",
      "Edit(~/.claude/**)",
      "Edit(~/.zshrc)",
      "Edit(~/.bashrc)",
      "Edit(~/.profile)",
      "Edit(/bin/**)",
      "Edit(/usr/**)",
      "Edit(/etc/**)"
    ]
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false,
    "excludedCommands": ["docker", "docker-compose"]
  }
}
EOF
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

build_prompt() {
    local agent=$1
    local base_file="$PROMPTS_DIR/_base.txt"
    local role_file="$PROMPTS_DIR/$agent.txt"

    if [[ ! -f "$role_file" ]]; then
        return 1
    fi

    # Combine base + role, substitute placeholders
    local agent_upper=$(echo "$agent" | tr '[:lower:]' '[:upper:]')
    local work_dir="${PROJECT_DIR:-$ORCHESTRATOR_HOME}"
    local base=$(cat "$base_file" | sed -e "s/{AGENT}/$agent_upper/g" -e "s|{PROJECT_DIR}|$work_dir|g" -e "s|{CHAT_LOG}|$CHAT_LOG|g")
    local role=$(cat "$role_file")

    # Git workflow only when --project is used
    local git_section=""
    if [[ -n "$PROJECT_DIR" ]]; then
        git_section="
GIT WORKFLOW:
- If no .git exists in project dir, run: git init
- IMMEDIATELY create a feature branch: git checkout -b feature/<short-name>
- Commit early and often with clear messages
- Complete ALL work on the feature branch
- DO NOT merge to main - leave the branch for human review
- When done, output DONE (human will review and merge)
"
    fi

    echo "$role
$git_section
$base"
}

run_agent() {
    local agent=$1
    local task="$2"

    local prompt=$(build_prompt "$agent")

    if [[ -z "$prompt" ]]; then
        echo -e "${RED}Unknown agent: $agent${NC}"
        return 1
    fi

    # Add task context if provided
    if [[ -n "$task" ]]; then
        prompt="$prompt

TASK FROM USER: $task"
    fi

    echo -e "${CYAN}[$agent's turn]${NC}"

    # Snapshot chat.log before
    local chat_before=$(wc -l < "$CHAT_LOG")

    # Check for existing session
    local session_id=$(get_session "$agent")
    local resume_flag=""
    if [[ -n "$session_id" ]]; then
        resume_flag="--resume $session_id"
        echo -e "${BLUE}(resuming session $session_id)${NC}"
    fi

    # Run claude (sandbox settings in .claude/settings.json handle permissions)
    log_debug "=== $agent turn ==="
    log_debug "Prompt: $prompt"

    local model=$(get_model "$agent")
    local work_dir="${PROJECT_DIR:-$ORCHESTRATOR_HOME}"

    log_debug "Model: $model, Working dir: $work_dir"

    # Ensure project has sandbox settings allowing access to orchestrator home
    ensure_project_settings "$work_dir"

    local output=$(cd "$work_dir" && claude -p "$prompt" \
        --model "$model" \
        --output-format json \
        $resume_flag 2>&1)

    log_debug "Raw output: $output"

    # Extract and save session_id for next time
    local new_session=$(echo "$output" | jq -r '.session_id // empty' 2>/dev/null | head -1)
    if [[ -n "$new_session" ]]; then
        set_session "$agent" "$new_session"
    fi

    # Show new chat entries
    local chat_after=$(wc -l < "$CHAT_LOG")
    if [[ $chat_after -gt $chat_before ]]; then
        echo -e "${YELLOW}--- chat.log update ---${NC}"
        tail -n +$((chat_before + 1)) "$CHAT_LOG" | head -20
        echo -e "${YELLOW}------------------------${NC}"
    fi

    # Extract the result text
    local result=$(echo "$output" | jq -r '.result // empty' 2>/dev/null)

    # Parse for NEXT: or DONE (flexible: case-insensitive, handles markdown bold **)
    local next_line=$(echo "$result" | grep -iE "^\*{0,2}[[:space:]]*(NEXT|next|Next)[[:space:]]*:[[:space:]]*(CEO|PM|DEV_JOHN|DEV_ALICE|DESIGNER_MAYA|DESIGNER_ALEX)" | tail -1)
    local done_line=$(echo "$result" | grep -iE "^\*{0,2}[[:space:]]*(DONE|done|Done)[[:space:]]*\*{0,2}[[:space:]]*$" | tail -1)

    if [[ -n "$done_line" ]]; then
        echo "DONE"
        return
    fi

    if [[ -n "$next_line" ]]; then
        # Extract agent name (include underscores for names like DEV_JOHN, DESIGNER_MAYA)
        local agent=$(echo "$next_line" | sed -E 's/.*[Nn][Ee][Xx][Tt][[:space:]]*:[[:space:]]*([A-Za-z_]+).*/\1/' | tr '[:upper:]' '[:lower:]')
        echo "NEXT: $agent"
        return
    fi

    echo -e "${YELLOW}Agent didn't output NEXT/DONE. Result:${NC}"
    echo "$result" | tail -5
    echo "DONE"
}

relay() {
    local start_agent="$1"
    shift
    local task="$*"

    local current="$start_agent"
    local turn=1

    echo -e "${GREEN}=== Starting relay with $start_agent ===${NC}"
    if [[ -n "$PROJECT_DIR" ]]; then
        echo -e "${BLUE}Project: $PROJECT_DIR${NC}"
    fi
    echo -e "${BLUE}Task: $task${NC}"
    echo ""

    while [[ $turn -le $MAX_TURNS ]]; do
        echo -e "${YELLOW}--- Turn $turn ---${NC}"

        # First turn gets the task, subsequent turns don't
        if [[ $turn -eq 1 ]]; then
            result=$(run_agent "$current" "$task")
        else
            result=$(run_agent "$current" "")
        fi

        echo -e "Output: $result"
        echo ""

        # Parse last line of result for the handoff
        local handoff=$(echo "$result" | tail -1)

        if [[ "$handoff" == "DONE" ]]; then
            echo -e "${GREEN}=== Relay complete ===${NC}"
            break
        elif [[ "$handoff" =~ ^NEXT:\ *(.+)$ ]]; then
            next="${BASH_REMATCH[1]}"
            # Normalize agent name
            next=$(echo "$next" | tr '[:lower:]' '[:upper:]' | xargs)
            current=$(echo "$next" | tr '[:upper:]' '[:lower:]')
            echo -e "${GREEN}Handing off to: $next${NC}"
        else
            echo -e "${RED}Invalid output: '$handoff'${NC}"
            break
        fi

        ((turn++))
    done

    if [[ $turn -gt $MAX_TURNS ]]; then
        echo -e "${RED}Max turns reached${NC}"
    fi

    echo ""
    echo -e "${YELLOW}=== Final chat.log ===${NC}"
    cat "$CHAT_LOG"
}

continue_relay() {
    local agent="$1"

    if [[ -z "$agent" ]]; then
        echo -e "${RED}Usage: $0 continue <agent>${NC}"
        echo "Pick up where you left off. Specify which agent should go next."
        exit 1
    fi

    echo -e "${GREEN}=== Continuing relay with $agent ===${NC}"
    echo -e "${YELLOW}--- Current chat.log ---${NC}"
    tail -10 "$CHAT_LOG"
    echo -e "${YELLOW}-------------------------${NC}"
    echo ""

    local current="$agent"
    local turn=1

    while [[ $turn -le $MAX_TURNS ]]; do
        echo -e "${YELLOW}--- Turn $turn ---${NC}"

        result=$(run_agent "$current" "")

        echo -e "Output: $result"
        echo ""

        local handoff=$(echo "$result" | tail -1)

        if [[ "$handoff" == "DONE" ]]; then
            echo -e "${GREEN}=== Relay complete ===${NC}"
            break
        elif [[ "$handoff" =~ ^NEXT:\ *(.+)$ ]]; then
            next="${BASH_REMATCH[1]}"
            next=$(echo "$next" | tr '[:lower:]' '[:upper:]' | xargs)
            current=$(echo "$next" | tr '[:upper:]' '[:lower:]')
            echo -e "${GREEN}Handing off to: $next${NC}"
        else
            echo -e "${RED}Invalid output: '$handoff'${NC}"
            break
        fi

        ((turn++))
    done

    echo ""
    echo -e "${YELLOW}=== Final chat.log ===${NC}"
    cat "$CHAT_LOG"
}

reset_sessions() {
    echo '{}' > "$SESSIONS_FILE"
    echo -e "${GREEN}Sessions cleared${NC}"
}

reset_all() {
    echo '{}' > "$SESSIONS_FILE"
    echo "# Agent Communication Log
# APPEND ONLY - never edit previous entries
---" > "$CHAT_LOG"
    rm -f "$DEBUG_LOG"
    echo -e "${GREEN}All state reset (sessions, chat, debug log)${NC}"
}

# Parse flags
NO_RESET=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            PROJECT_DIR="$2"
            shift 2
            ;;
        --no-reset)
            NO_RESET=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Usage
if [[ $# -lt 1 ]]; then
    echo "Usage:"
    echo "  $0 [--project <dir>] [--no-reset] <agent> <task>   Start new relay (resets by default)"
    echo "  $0 [--project <dir>] continue <agent>              Continue from where you left off"
    echo ""
    echo "Agents: ceo, pm, dev_john, dev_alice, designer_maya, designer_alex"
    echo "Models: dev agents use opus, others use sonnet"
    echo "Debug log: $DEBUG_LOG"
    exit 1
fi

case "$1" in
    continue)
        continue_relay "$2"
        ;;
    *)
        # Reset by default unless --no-reset
        if [[ "$NO_RESET" == "false" ]]; then
            reset_all
        fi
        relay "$@"
        ;;
esac
