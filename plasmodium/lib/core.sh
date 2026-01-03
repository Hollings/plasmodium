#!/bin/bash
# Plasmodium v2 - Core library
# All the functions that make the magic happen

# ============================================================================
# Configuration
# ============================================================================

# Tree names for agents
TREE_NAMES=(oak cedar pine maple birch ash willow hazel elm beech alder rowan holly ivy yew)

# ============================================================================
# Utility Functions
# ============================================================================

gen_id() {
    local prefix="$1"
    echo "${prefix}-$(openssl rand -hex 3)"
}

gen_agent_name() {
    local tree="${TREE_NAMES[$RANDOM % ${#TREE_NAMES[@]}]}"
    local suffix=$(openssl rand -hex 2)
    echo "${tree}_${suffix}"
}

get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

get_pm_dir() {
    # Find .plasmodium directory (walk up from cwd)
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.plasmodium" ]]; then
            echo "$dir/.plasmodium"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo ""
    return 1
}

get_project_dir() {
    local pm_dir=$(get_pm_dir)
    if [[ -n "$pm_dir" ]]; then
        dirname "$pm_dir"
    fi
}

require_pm_dir() {
    local pm_dir=$(get_pm_dir)
    if [[ -z "$pm_dir" ]]; then
        echo "Error: Not in a plasmodium project. Run 'pm init' first." >&2
        exit 1
    fi
    echo "$pm_dir"
}

# ============================================================================
# Agent Identity
# ============================================================================

get_agent_name() {
    # Agent name comes from environment variable set during spawn
    echo "${PM_AGENT_NAME:-}"
}

get_agent_task() {
    echo "${PM_TASK_ID:-}"
}

get_agent_phase() {
    echo "${PM_PHASE_ID:-}"
}

get_agent_role() {
    echo "${PM_ROLE:-}"
}

is_agent() {
    [[ -n "$(get_agent_name)" ]]
}

# ============================================================================
# Task Functions
# ============================================================================

get_task() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local task_file="$pm_dir/tasks/$task_id/task.json"
    if [[ -f "$task_file" ]]; then
        cat "$task_file"
    fi
}

list_tasks() {
    local pm_dir=$(require_pm_dir)
    local tasks_dir="$pm_dir/tasks"
    if [[ -d "$tasks_dir" ]]; then
        for task_dir in "$tasks_dir"/*/; do
            if [[ -f "${task_dir}task.json" ]]; then
                cat "${task_dir}task.json"
            fi
        done
    fi
}

create_task() {
    local pm_dir=$(require_pm_dir)
    local description="$1"
    local parent_id="${2:-}"

    local task_id=$(gen_id "tk")
    local task_dir="$pm_dir/tasks/$task_id"
    mkdir -p "$task_dir/phases"

    local owner=$(gen_agent_name)

    cat > "$task_dir/task.json" << EOF
{
  "id": "$task_id",
  "description": "$description",
  "owner": "$owner",
  "parent_id": ${parent_id:+\"$parent_id\"}${parent_id:-null},
  "status": "active",
  "created_at": "$(get_timestamp)"
}
EOF

    echo "$task_id"
}

update_task_status() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local status="$2"
    local task_file="$pm_dir/tasks/$task_id/task.json"

    if [[ ! -f "$task_file" ]]; then
        echo "Error: Task not found: $task_id" >&2
        return 1
    fi

    local tmp=$(mktemp)
    jq --arg status "$status" '.status = $status' "$task_file" > "$tmp"
    mv "$tmp" "$task_file"
}

# ============================================================================
# Phase Functions
# ============================================================================

get_phase() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"
    local phase_file="$pm_dir/tasks/$task_id/phases/$phase_id/phase.json"
    if [[ -f "$phase_file" ]]; then
        cat "$phase_file"
    fi
}

get_active_phase() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phases_dir="$pm_dir/tasks/$task_id/phases"

    if [[ -d "$phases_dir" ]]; then
        for phase_dir in "$phases_dir"/*/; do
            if [[ -f "${phase_dir}phase.json" ]]; then
                local status=$(jq -r '.status' "${phase_dir}phase.json")
                if [[ "$status" == "active" ]]; then
                    cat "${phase_dir}phase.json"
                    return 0
                fi
            fi
        done
    fi
    return 1
}

create_phase() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local name="$2"
    local limit="$3"
    shift 3
    local roles=("$@")

    local phase_id=$(gen_id "ph")
    local phase_dir="$pm_dir/tasks/$task_id/phases/$phase_id"
    mkdir -p "$phase_dir"

    # Create roles JSON array
    local roles_json=$(printf '%s\n' "${roles[@]}" | jq -R . | jq -s .)

    cat > "$phase_dir/phase.json" << EOF
{
  "id": "$phase_id",
  "task_id": "$task_id",
  "name": "$name",
  "message_limit": $limit,
  "roles": $roles_json,
  "status": "active",
  "created_at": "$(get_timestamp)"
}
EOF

    # Create empty messages file
    touch "$phase_dir/messages.jsonl"

    echo "$phase_id"
}

get_message_count() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"
    local messages_file="$pm_dir/tasks/$task_id/phases/$phase_id/messages.jsonl"

    if [[ -f "$messages_file" ]]; then
        wc -l < "$messages_file" | tr -d ' '
    else
        echo "0"
    fi
}

append_message() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"
    local author="$3"
    local role="$4"
    local content="$5"

    local messages_file="$pm_dir/tasks/$task_id/phases/$phase_id/messages.jsonl"
    local msg_id=$(gen_id "msg")

    # Escape content for JSON
    local escaped_content=$(echo "$content" | jq -Rs .)

    # Build role JSON value
    local role_json="null"
    if [[ -n "$role" ]]; then
        role_json="\"$role\""
    fi

    echo "{\"id\":\"$msg_id\",\"author\":\"$author\",\"role\":$role_json,\"content\":$escaped_content,\"timestamp\":\"$(get_timestamp)\"}" >> "$messages_file"
}

close_phase() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"
    local phase_file="$pm_dir/tasks/$task_id/phases/$phase_id/phase.json"

    if [[ ! -f "$phase_file" ]]; then
        echo "Error: Phase not found" >&2
        return 1
    fi

    local tmp=$(mktemp)
    jq '.status = "closed"' "$phase_file" > "$tmp"
    mv "$tmp" "$phase_file"

    # Unregister all role agents for this phase
    local agents_file="$pm_dir/agents.json"
    if [[ -f "$agents_file" ]]; then
        tmp=$(mktemp)
        jq --arg phase_id "$phase_id" \
           '.agents = (.agents | to_entries | map(select(.value.phase_id != $phase_id)) | from_entries)' \
           "$agents_file" > "$tmp"
        mv "$tmp" "$agents_file"
    fi
}

# ============================================================================
# Agent Registry
# ============================================================================

register_agent() {
    local pm_dir=$(require_pm_dir)
    local name="$1"
    local task_id="$2"
    local phase_id="${3:-}"
    local role="${4:-}"
    local pid="${5:-}"

    local agents_file="$pm_dir/agents.json"

    # Initialize if doesn't exist
    if [[ ! -f "$agents_file" ]]; then
        echo '{"agents":{}}' > "$agents_file"
    fi

    local tmp=$(mktemp)
    jq --arg name "$name" \
       --arg task_id "$task_id" \
       --arg phase_id "$phase_id" \
       --arg role "$role" \
       --arg pid "$pid" \
       --arg timestamp "$(get_timestamp)" \
       '.agents[$name] = {
         "name": $name,
         "task_id": $task_id,
         "phase_id": (if $phase_id == "" then null else $phase_id end),
         "role": (if $role == "" then null else $role end),
         "pid": (if $pid == "" then null else ($pid | tonumber) end),
         "registered_at": $timestamp
       }' "$agents_file" > "$tmp"
    mv "$tmp" "$agents_file"
}

unregister_agent() {
    local pm_dir=$(require_pm_dir)
    local name="$1"
    local agents_file="$pm_dir/agents.json"

    if [[ -f "$agents_file" ]]; then
        local tmp=$(mktemp)
        jq --arg name "$name" 'del(.agents[$name])' "$agents_file" > "$tmp"
        mv "$tmp" "$agents_file"
    fi
}

list_agents() {
    local pm_dir=$(require_pm_dir)
    local agents_file="$pm_dir/agents.json"

    if [[ -f "$agents_file" ]]; then
        jq -r '.agents | to_entries[] | .value' "$agents_file"
    fi
}

# ============================================================================
# Agent Spawning
# ============================================================================

spawn_agent() {
    local name="$1"
    local task_id="$2"
    local prompt_file="$3"
    local phase_id="${4:-}"
    local role="${5:-}"

    local pm_dir=$(require_pm_dir)
    local project_dir=$(get_project_dir)
    local log_dir="$pm_dir/logs"
    mkdir -p "$log_dir"

    # Read and substitute prompt
    local prompt=$(cat "$prompt_file")
    prompt="${prompt//\{NAME\}/$name}"
    prompt="${prompt//\{TASK_ID\}/$task_id}"
    prompt="${prompt//\{PHASE_ID\}/$phase_id}"
    prompt="${prompt//\{ROLE\}/$role}"

    # Get task description
    local task=$(get_task "$task_id")
    local task_desc=$(echo "$task" | jq -r '.description')
    prompt="${prompt//\{TASK_DESCRIPTION\}/$task_desc}"

    # Get phase info if applicable
    if [[ -n "$phase_id" ]]; then
        local phase=$(get_phase "$task_id" "$phase_id")
        local phase_name=$(echo "$phase" | jq -r '.name')
        local phase_limit=$(echo "$phase" | jq -r '.message_limit')
        prompt="${prompt//\{PHASE_NAME\}/$phase_name}"
        prompt="${prompt//\{PHASE_LIMIT\}/$phase_limit}"
    fi

    # Spawn Claude Code in background
    (
        cd "$project_dir"
        PM_AGENT_NAME="$name" \
        PM_TASK_ID="$task_id" \
        PM_PHASE_ID="$phase_id" \
        PM_ROLE="$role" \
        PM_CLI="$PM_CLI" \
        claude --dangerously-skip-permissions -p "$prompt" \
            > "$log_dir/${name}.log" 2>&1
    ) &

    local pid=$!

    # Register agent
    register_agent "$name" "$task_id" "$phase_id" "$role" "$pid"

    echo "$name (pid: $pid)"
}

spawn_agent_with_perspective() {
    local name="$1"
    local task_id="$2"
    local phase_id="$3"
    local perspective="$4"

    local pm_dir=$(require_pm_dir)
    local project_dir=$(get_project_dir)
    local log_dir="$pm_dir/logs"
    mkdir -p "$log_dir"

    # Read generic agent prompt
    local prompt_file="$PM_SCRIPT_DIR/prompts/agent.md"
    if [[ ! -f "$prompt_file" ]]; then
        echo "Error: Agent prompt not found at $prompt_file" >&2
        return 1
    fi

    local prompt=$(cat "$prompt_file")
    prompt="${prompt//\{NAME\}/$name}"
    prompt="${prompt//\{PERSPECTIVE\}/$perspective}"

    # Get task description
    local task=$(get_task "$task_id")
    local task_desc=$(echo "$task" | jq -r '.description')
    prompt="${prompt//\{TASK_DESCRIPTION\}/$task_desc}"

    # Get phase info
    local phase=$(get_phase "$task_id" "$phase_id")
    local phase_name=$(echo "$phase" | jq -r '.name')
    local phase_limit=$(echo "$phase" | jq -r '.message_limit')
    prompt="${prompt//\{PHASE_NAME\}/$phase_name}"
    prompt="${prompt//\{PHASE_LIMIT\}/$phase_limit}"

    # Spawn Claude Code in background
    (
        cd "$project_dir"
        PM_AGENT_NAME="$name" \
        PM_TASK_ID="$task_id" \
        PM_PHASE_ID="$phase_id" \
        PM_ROLE="$perspective" \
        PM_CLI="$PM_CLI" \
        claude --dangerously-skip-permissions -p "$prompt" \
            > "$log_dir/${name}.log" 2>&1
    ) &

    local pid=$!

    # Register agent (use perspective as role for display)
    register_agent "$name" "$task_id" "$phase_id" "$perspective" "$pid"

    echo "$name (pid: $pid)"
}

# ============================================================================
# Command Implementations
# ============================================================================

pm_init() {
    local pm_dir=".plasmodium"

    if [[ -d "$pm_dir" ]]; then
        echo "Already initialized"
        return 0
    fi

    mkdir -p "$pm_dir/tasks"
    mkdir -p "$pm_dir/logs"

    cat > "$pm_dir/config.json" << EOF
{
  "version": "2.0.0",
  "project_path": "$PWD",
  "created_at": "$(get_timestamp)"
}
EOF

    echo '{"agents":{}}' > "$pm_dir/agents.json"

    echo "Initialized plasmodium in $PWD"
}

pm_reset() {
    local pm_dir=$(require_pm_dir)

    echo "Resetting plasmodium state..."

    # Kill all agents
    if [[ -f "$pm_dir/agents.json" ]]; then
        local pids=$(jq -r '.agents[].pid // empty' "$pm_dir/agents.json")
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
    fi

    # Clear state
    rm -rf "$pm_dir/tasks"
    mkdir -p "$pm_dir/tasks"
    echo '{"agents":{}}' > "$pm_dir/agents.json"
    rm -f "$pm_dir/logs"/*.log

    echo "Reset complete"
}

pm_task() {
    local description="$1"

    if [[ -z "$description" ]]; then
        echo "Usage: pm task \"description\"" >&2
        exit 1
    fi

    local task_id=$(create_task "$description")
    local task=$(get_task "$task_id")
    local owner=$(echo "$task" | jq -r '.owner')

    echo "Created task: $task_id"
    echo "Owner: @$owner"

    # Spawn owner agent
    local prompt_file="$PM_SCRIPT_DIR/prompts/owner.md"
    if [[ ! -f "$prompt_file" ]]; then
        echo "Warning: Owner prompt not found at $prompt_file" >&2
        echo "Agent not spawned - create the prompt file first" >&2
        return 0
    fi

    echo "Spawning owner agent..."
    spawn_agent "$owner" "$task_id" "$prompt_file"
}

pm_status() {
    local pm_dir=$(require_pm_dir)

    echo "=== Tasks ==="
    list_tasks | jq -r '"[\(.status)] \(.id): \(.description) (owner: @\(.owner))"'

    echo ""
    echo "=== Agents ==="
    list_agents | jq -r '"@\(.name) - task:\(.task_id) phase:\(.phase_id // "none") role:\(.role // "owner")"'
}

pm_phase() {
    local name=""
    local limit=10
    local perspectives=()

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit)
                limit="$2"
                shift 2
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                else
                    # Additional positional args are perspectives
                    perspectives+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        echo "Usage: pm phase \"Name\" --limit N \"perspective 1\" \"perspective 2\"" >&2
        exit 1
    fi

    # Get task ID from environment (agent) or error
    local task_id=$(get_agent_task)
    if [[ -z "$task_id" ]]; then
        echo "Error: pm phase can only be called by an owner agent" >&2
        exit 1
    fi

    # Check limit on perspectives
    if [[ ${#perspectives[@]} -gt 3 ]]; then
        echo "Error: Maximum 3 agents per phase" >&2
        exit 1
    fi

    if [[ ${#perspectives[@]} -lt 2 ]]; then
        echo "Error: At least 2 perspectives required for a discussion" >&2
        echo "Example: pm phase \"Design\" --limit 8 \"skeptical architect\" \"eager builder\"" >&2
        exit 1
    fi

    # Create phase (store perspectives as roles for backwards compat)
    local phase_id=$(create_phase "$task_id" "$name" "$limit" "${perspectives[@]}")
    echo "Created phase: $phase_id ($name)"
    echo "Message limit: $limit"
    echo "Agents: ${#perspectives[@]}"

    # Collect agent names as we spawn them
    local agent_names=()

    # Spawn agents with perspectives
    for perspective in "${perspectives[@]}"; do
        local agent_name=$(gen_agent_name)
        agent_names+=("$agent_name")
        echo "Spawning @$agent_name: $perspective"
        spawn_agent_with_perspective "$agent_name" "$task_id" "$phase_id" "$perspective"
    done

    # Post intro message listing who's in the room
    local intro="Phase '$name' started. In this room:\n"
    for i in "${!agent_names[@]}"; do
        intro+="- @${agent_names[$i]}: ${perspectives[$i]}\n"
    done
    intro+="\nDiscuss and reach a conclusion."
    append_message "$task_id" "$phase_id" "system" "" "$(echo -e "$intro")"
}

pm_chat() {
    local task_id=$(get_agent_task)
    local phase_id=$(get_agent_phase)

    # If not an agent, try to find active phase from args or show all
    if [[ -z "$task_id" ]]; then
        echo "Error: pm chat can only be called by an agent" >&2
        exit 1
    fi

    if [[ -z "$phase_id" ]]; then
        # Owner - find active phase
        local phase=$(get_active_phase "$task_id")
        if [[ -z "$phase" ]]; then
            echo "No active phase"
            return 0
        fi
        phase_id=$(echo "$phase" | jq -r '.id')
    fi

    local pm_dir=$(require_pm_dir)
    local messages_file="$pm_dir/tasks/$task_id/phases/$phase_id/messages.jsonl"
    local phase=$(get_phase "$task_id" "$phase_id")
    local limit=$(echo "$phase" | jq -r '.message_limit')
    local count=$(get_message_count "$task_id" "$phase_id")
    local status=$(echo "$phase" | jq -r '.status')

    echo "=== Phase: $(echo "$phase" | jq -r '.name') ($count/$limit messages) [$status] ==="
    echo ""

    if [[ -f "$messages_file" ]] && [[ -s "$messages_file" ]]; then
        while IFS= read -r line; do
            local author=$(echo "$line" | jq -r '.author')
            local role=$(echo "$line" | jq -r '.role // empty')
            local content=$(echo "$line" | jq -r '.content')
            local role_str=""
            [[ -n "$role" ]] && role_str=" ($role)"
            echo "@${author}${role_str}: $content"
        done < "$messages_file"
    else
        echo "(no messages yet)"
    fi
}

pm_say() {
    local content="$1"

    if [[ -z "$content" ]]; then
        echo "Usage: pm say \"message\"" >&2
        exit 1
    fi

    local task_id=$(get_agent_task)
    local phase_id=$(get_agent_phase)
    local agent_name=$(get_agent_name)
    local role=$(get_agent_role)

    if [[ -z "$task_id" ]]; then
        echo "Error: pm say can only be called by an agent" >&2
        exit 1
    fi

    if [[ -z "$phase_id" ]]; then
        # Owner - find active phase
        local phase=$(get_active_phase "$task_id")
        if [[ -z "$phase" ]]; then
            echo "Error: No active phase" >&2
            exit 1
        fi
        phase_id=$(echo "$phase" | jq -r '.id')
    fi

    # Check if phase is still active
    local phase=$(get_phase "$task_id" "$phase_id")
    local status=$(echo "$phase" | jq -r '.status')
    if [[ "$status" != "active" ]]; then
        echo "Error: Phase is closed" >&2
        exit 1
    fi

    # Check message limit
    local limit=$(echo "$phase" | jq -r '.message_limit')
    local count=$(get_message_count "$task_id" "$phase_id")

    if [[ $count -ge $limit ]]; then
        echo "Error: Phase message limit reached ($count/$limit)" >&2
        close_phase "$task_id" "$phase_id"
        exit 1
    fi

    # Append message
    append_message "$task_id" "$phase_id" "$agent_name" "$role" "$content"

    # Check if we just hit the limit
    count=$((count + 1))
    if [[ $count -ge $limit ]]; then
        close_phase "$task_id" "$phase_id"
        echo "Message posted ($count/$limit) - phase closed"
    else
        echo "Message posted ($count/$limit)"
    fi
}

pm_end_phase() {
    local task_id=$(get_agent_task)

    if [[ -z "$task_id" ]]; then
        echo "Error: pm end-phase can only be called by an owner agent" >&2
        exit 1
    fi

    local phase=$(get_active_phase "$task_id")
    if [[ -z "$phase" ]]; then
        echo "Error: No active phase" >&2
        exit 1
    fi

    local phase_id=$(echo "$phase" | jq -r '.id')
    close_phase "$task_id" "$phase_id"
    echo "Phase closed: $phase_id"
}

pm_done() {
    local task_id=$(get_agent_task)
    local agent_name=$(get_agent_name)
    local force=false

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$task_id" ]]; then
        echo "Error: pm done can only be called by an owner agent" >&2
        exit 1
    fi

    local pm_dir=$(require_pm_dir)
    local phases_dir="$pm_dir/tasks/$task_id/phases"

    # Check phase requirements (unless --force)
    if [[ "$force" != true ]]; then
        # Count closed phases
        local phase_count=0
        if [[ -d "$phases_dir" ]]; then
            for phase_dir in "$phases_dir"/*/; do
                if [[ -f "${phase_dir}phase.json" ]]; then
                    local status=$(jq -r '.status' "${phase_dir}phase.json")
                    if [[ "$status" == "closed" ]]; then
                        phase_count=$((phase_count + 1))
                    fi
                fi
            done
        fi

        if [[ $phase_count -eq 0 ]]; then
            echo "Error: At least one discussion phase required before completing." >&2
            echo "" >&2
            echo "Create a phase to get other perspectives:" >&2
            echo "  pm phase \"Design\" --limit 6 \"skeptical reviewer\" \"eager builder\"" >&2
            echo "" >&2
            echo "Or use --force to skip (not recommended):" >&2
            echo "  pm done --force" >&2
            exit 1
        fi

        # Check minimum messages in phases
        local min_messages=4
        for phase_dir in "$phases_dir"/*/; do
            if [[ -f "${phase_dir}messages.jsonl" ]]; then
                local msg_count=$(wc -l < "${phase_dir}messages.jsonl" | tr -d ' ')
                if [[ $msg_count -lt $min_messages ]]; then
                    local phase_name=$(jq -r '.name' "${phase_dir}phase.json")
                    echo "Error: Phase '$phase_name' has only $msg_count messages (minimum: $min_messages)" >&2
                    echo "Discussions need substance. Extend the phase or create a new one." >&2
                    exit 1
                fi
            fi
        done
    fi

    # Close any active phase
    local phase=$(get_active_phase "$task_id")
    if [[ -n "$phase" ]]; then
        local phase_id=$(echo "$phase" | jq -r '.id')
        close_phase "$task_id" "$phase_id"
    fi

    # Update task status
    update_task_status "$task_id" "done"

    # Unregister self
    unregister_agent "$agent_name"

    echo "Task complete: $task_id"
}

pm_extend_phase() {
    local additional="$1"

    if [[ -z "$additional" ]]; then
        echo "Usage: pm extend-phase N" >&2
        exit 1
    fi

    local task_id=$(get_agent_task)
    if [[ -z "$task_id" ]]; then
        echo "Error: pm extend-phase can only be called by an owner agent" >&2
        exit 1
    fi

    local phase=$(get_active_phase "$task_id")
    if [[ -z "$phase" ]]; then
        echo "Error: No active phase" >&2
        exit 1
    fi

    local phase_id=$(echo "$phase" | jq -r '.id')
    local pm_dir=$(require_pm_dir)
    local phase_file="$pm_dir/tasks/$task_id/phases/$phase_id/phase.json"

    local current_limit=$(echo "$phase" | jq -r '.message_limit')
    local new_limit=$((current_limit + additional))

    # Check max limit
    if [[ $new_limit -gt 50 ]]; then
        echo "Error: Cannot exceed 50 messages per phase" >&2
        exit 1
    fi

    local tmp=$(mktemp)
    jq --argjson limit "$new_limit" '.message_limit = $limit' "$phase_file" > "$tmp"
    mv "$tmp" "$phase_file"

    echo "Phase limit extended: $current_limit -> $new_limit"
}

pm_history() {
    # Placeholder - will implement later
    echo "pm history not yet implemented"
}

pm_subtask() {
    # Placeholder - will implement later
    echo "pm subtask not yet implemented"
}

pm_wait_children() {
    # Placeholder - will implement later
    echo "pm wait-children not yet implemented"
}

pm_kill() {
    local task_id="$1"
    local restart=false

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --restart)
                restart=true
                shift
                ;;
            *)
                if [[ -z "$task_id" || "$task_id" == --* ]]; then
                    task_id="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$task_id" ]]; then
        echo "Usage: pm kill <task-id> [--restart]" >&2
        exit 1
    fi

    local pm_dir=$(require_pm_dir)
    local task=$(get_task "$task_id")

    if [[ -z "$task" ]]; then
        echo "Error: Task not found: $task_id" >&2
        exit 1
    fi

    local description=$(echo "$task" | jq -r '.description')

    echo "Killing task: $task_id"

    # Find and kill all agents for this task
    local agents_file="$pm_dir/agents.json"
    if [[ -f "$agents_file" ]]; then
        local pids=$(jq -r --arg task_id "$task_id" \
            '.agents[] | select(.task_id == $task_id) | .pid // empty' \
            "$agents_file")

        for pid in $pids; do
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                echo "  Killing agent (pid: $pid)"
                kill "$pid" 2>/dev/null || true
            fi
        done

        # Remove agents from registry
        local tmp=$(mktemp)
        jq --arg task_id "$task_id" \
           '.agents = (.agents | to_entries | map(select(.value.task_id != $task_id)) | from_entries)' \
           "$agents_file" > "$tmp"
        mv "$tmp" "$agents_file"
    fi

    if [[ "$restart" == true ]]; then
        echo "Restarting task..."
        # Reset task status
        update_task_status "$task_id" "active"

        # Spawn new owner
        local owner=$(gen_agent_name)
        local task_file="$pm_dir/tasks/$task_id/task.json"
        local tmp=$(mktemp)
        jq --arg owner "$owner" '.owner = $owner' "$task_file" > "$tmp"
        mv "$tmp" "$task_file"

        local prompt_file="$PM_SCRIPT_DIR/prompts/owner.md"
        echo "Spawning new owner @$owner..."
        spawn_agent "$owner" "$task_id" "$prompt_file"
    else
        # Mark task as killed
        update_task_status "$task_id" "killed"
        echo "Task killed"
    fi
}

pm_clean() {
    local pm_dir=$(require_pm_dir)
    local agents_file="$pm_dir/agents.json"

    if [[ ! -f "$agents_file" ]]; then
        echo "No agents to clean"
        return 0
    fi

    local cleaned=0
    local names=$(jq -r '.agents | keys[]' "$agents_file")

    for name in $names; do
        local pid=$(jq -r --arg name "$name" '.agents[$name].pid // empty' "$agents_file")

        # Check if process is dead
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            echo "Removing dead agent: @$name (pid: $pid)"
            local tmp=$(mktemp)
            jq --arg name "$name" 'del(.agents[$name])' "$agents_file" > "$tmp"
            mv "$tmp" "$agents_file"
            cleaned=$((cleaned + 1))
        fi
    done

    if [[ $cleaned -eq 0 ]]; then
        echo "No dead agents found"
    else
        echo "Cleaned $cleaned dead agent(s)"
    fi
}

pm_dashboard() {
    # Placeholder - will implement later
    echo "pm dashboard not yet implemented"
}
