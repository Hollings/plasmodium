#!/bin/bash
# Multi-agent relay orchestrator
# Each agent gets one turn, outputs "NEXT: <agent>" or "DONE"

# Determine script location for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/agent-prompts"

# Workspace lives in target project
WORKSPACE_DIR=""
CHAT_LOG=""
SESSIONS_FILE=""
DEBUG_LOG=""
OUTPUT_LOG=""

MAX_TURNS=50

init_workspace() {
    local project_dir="$1"
    WORKSPACE_DIR="$project_dir/.team-relay"
    mkdir -p "$WORKSPACE_DIR"

    CHAT_LOG="$WORKSPACE_DIR/chat.log"
    SESSIONS_FILE="$WORKSPACE_DIR/sessions.json"
    DEBUG_LOG="$WORKSPACE_DIR/debug.log"
    OUTPUT_LOG="$WORKSPACE_DIR/output.log"

    # Initialize files if needed
    if [[ ! -f "$SESSIONS_FILE" ]]; then
        echo '{}' > "$SESSIONS_FILE"
    fi
    if [[ ! -f "$CHAT_LOG" ]]; then
        echo "# Agent Communication Log
# APPEND ONLY - never edit previous entries
---" > "$CHAT_LOG"
    fi
}

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

log_output() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$OUTPUT_LOG"
}

get_model() {
    local agent=$1
    case "$agent" in
        dev_john|dev_alice|qa_andrew|designer_maya) echo "opus" ;;
        designer_alex) echo "haiku" ;;
        *) echo "sonnet" ;;
    esac
}

build_prompt() {
    local agent=$1
    local project_dir=$2
    local base_file="$PROMPTS_DIR/_base.txt"
    local role_file="$PROMPTS_DIR/$agent.txt"

    if [[ ! -f "$role_file" ]]; then
        return 1
    fi

    local agent_upper=$(echo "$agent" | tr '[:lower:]' '[:upper:]')
    local base=$(cat "$base_file" | sed -e "s/{AGENT}/$agent_upper/g" -e "s|{PROJECT_DIR}|$project_dir|g" -e "s|{CHAT_LOG}|$CHAT_LOG|g")
    local role=$(cat "$role_file")

    # Git workflow section
    local git_section="
GIT WORKFLOW:
- If no .git exists in project dir, run: git init
- IMMEDIATELY create a feature branch: git checkout -b feature/<short-name>
- Commit early and often with clear messages
- Complete ALL work on the feature branch
- DO NOT merge to main - leave the branch for human review
- When done, output DONE (human will review and merge)
"

    echo "$role
$git_section
$base"
}

run_agent() {
    local agent=$1
    local task="$2"
    local project_dir="$3"

    local prompt=$(build_prompt "$agent" "$project_dir")

    if [[ -z "$prompt" ]]; then
        log_output "ERROR: Unknown agent: $agent"
        return 1
    fi

    if [[ -n "$task" ]]; then
        prompt="$prompt

TASK FROM USER: $task"
    fi

    log_output ">>> $agent's turn"
    log_debug "=== $agent turn ==="
    log_debug "Prompt: $prompt"

    local chat_before=$(wc -l < "$CHAT_LOG")

    local session_id=$(get_session "$agent")
    local resume_flag=""
    if [[ -n "$session_id" ]]; then
        resume_flag="--resume $session_id"
        log_output "(resuming session)"
    fi

    local model=$(get_model "$agent")
    log_debug "Model: $model, Working dir: $project_dir"

    local output=$(cd "$project_dir" && claude -p "$prompt" \
        --model "$model" \
        --output-format json \
        --permission-mode acceptEdits \
        $resume_flag 2>&1)

    log_debug "Raw output: $output"

    local new_session=$(echo "$output" | jq -r '.session_id // empty' 2>/dev/null | head -1)
    if [[ -n "$new_session" ]]; then
        set_session "$agent" "$new_session"
    fi

    # Log new chat entries
    local chat_after=$(wc -l < "$CHAT_LOG")
    if [[ $chat_after -gt $chat_before ]]; then
        log_output "--- chat update ---"
        tail -n +$((chat_before + 1)) "$CHAT_LOG" | while read line; do
            log_output "$line"
        done
    fi

    local result=$(echo "$output" | jq -r '.result // empty' 2>/dev/null)

    # Parse for NEXT: or DONE
    local next_line=$(echo "$result" | grep -iE "^\*{0,2}[[:space:]]*(NEXT|next|Next)[[:space:]]*:[[:space:]]*(CEO|PM|DEV_JOHN|DEV_ALICE|DESIGNER_MAYA|DESIGNER_ALEX|QA_ANDREW)" | tail -1)
    local done_line=$(echo "$result" | grep -iE "^\*{0,2}[[:space:]]*(DONE|done|Done)[[:space:]]*\*{0,2}[[:space:]]*$" | tail -1)

    if [[ -n "$done_line" ]]; then
        echo "DONE"
        return
    fi

    if [[ -n "$next_line" ]]; then
        local next_agent=$(echo "$next_line" | sed -E 's/.*[Nn][Ee][Xx][Tt][[:space:]]*:[[:space:]]*([A-Za-z_]+).*/\1/' | tr '[:upper:]' '[:lower:]')
        echo "NEXT: $next_agent"
        return
    fi

    log_output "Agent didn't output NEXT/DONE"
    echo "DONE"
}

relay() {
    local project_dir="$1"
    local start_agent="$2"
    shift 2
    local task="$*"

    init_workspace "$project_dir"

    log_output "=== RELAY STARTED ==="
    log_output "Project: $project_dir"
    log_output "Starting agent: $start_agent"
    log_output "Task: $task"

    local current="$start_agent"
    local turn=1

    while [[ $turn -le $MAX_TURNS ]]; do
        log_output "--- Turn $turn: $current ---"

        if [[ $turn -eq 1 ]]; then
            result=$(run_agent "$current" "$task" "$project_dir")
        else
            result=$(run_agent "$current" "" "$project_dir")
        fi

        local handoff=$(echo "$result" | tail -1)

        if [[ "$handoff" == "DONE" ]]; then
            log_output "=== RELAY COMPLETE ==="
            break
        elif [[ "$handoff" =~ ^NEXT:\ *(.+)$ ]]; then
            next="${BASH_REMATCH[1]}"
            current=$(echo "$next" | tr '[:upper:]' '[:lower:]')
            log_output "Handing off to: $current"
        else
            log_output "ERROR: Invalid output: '$handoff'"
            break
        fi

        ((turn++))
    done

    if [[ $turn -gt $MAX_TURNS ]]; then
        log_output "ERROR: Max turns ($MAX_TURNS) reached"
    fi
}

continue_relay() {
    local project_dir="$1"
    local agent="$2"

    init_workspace "$project_dir"

    if [[ -z "$agent" ]]; then
        echo "Usage: $0 continue <project_dir> <agent>"
        exit 1
    fi

    log_output "=== CONTINUING RELAY ==="
    log_output "Agent: $agent"

    local current="$agent"
    local turn=1

    while [[ $turn -le $MAX_TURNS ]]; do
        log_output "--- Turn $turn: $current ---"

        result=$(run_agent "$current" "" "$project_dir")
        local handoff=$(echo "$result" | tail -1)

        if [[ "$handoff" == "DONE" ]]; then
            log_output "=== RELAY COMPLETE ==="
            break
        elif [[ "$handoff" =~ ^NEXT:\ *(.+)$ ]]; then
            next="${BASH_REMATCH[1]}"
            current=$(echo "$next" | tr '[:upper:]' '[:lower:]')
            log_output "Handing off to: $current"
        else
            log_output "ERROR: Invalid output: '$handoff'"
            break
        fi

        ((turn++))
    done
}

reset_workspace() {
    local project_dir="$1"
    init_workspace "$project_dir"

    echo '{}' > "$SESSIONS_FILE"
    echo "# Agent Communication Log
# APPEND ONLY - never edit previous entries
---" > "$CHAT_LOG"
    rm -f "$DEBUG_LOG" "$OUTPUT_LOG"

    log_output "Workspace reset"
}

# Main
case "$1" in
    start)
        # start <project_dir> <agent> <task...>
        shift
        project_dir="$1"
        shift
        agent="$1"
        shift
        task="$*"
        relay "$project_dir" "$agent" "$task"
        ;;
    continue)
        # continue <project_dir> <agent>
        shift
        continue_relay "$1" "$2"
        ;;
    reset)
        # reset <project_dir>
        shift
        reset_workspace "$1"
        ;;
    *)
        echo "Team Relay Orchestrator"
        echo ""
        echo "Usage:"
        echo "  $0 start <project_dir> <agent> <task...>"
        echo "  $0 continue <project_dir> <agent>"
        echo "  $0 reset <project_dir>"
        echo ""
        echo "Agents: ceo, pm, dev_john, dev_alice, designer_maya, designer_alex, qa_andrew"
        exit 1
        ;;
esac
