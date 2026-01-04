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
    local project_dir=$(get_project_dir)
    local description="$1"
    local parent_id="${2:-}"

    local task_id=$(gen_id "tk")
    local task_dir="$pm_dir/tasks/$task_id"
    mkdir -p "$task_dir/phases"

    local owner=$(gen_agent_name)
    local branch_name="task/$task_id"
    local worktree_path="$pm_dir/worktrees/$task_id"

    # Create branch from current HEAD
    git -C "$project_dir" branch "$branch_name" HEAD 2>/dev/null || {
        echo "Error: Failed to create branch $branch_name" >&2
        return 1
    }

    # Create worktree for this task
    mkdir -p "$pm_dir/worktrees"
    git -C "$project_dir" worktree add "$worktree_path" "$branch_name" 2>/dev/null || {
        echo "Error: Failed to create worktree at $worktree_path" >&2
        git -C "$project_dir" branch -d "$branch_name" 2>/dev/null
        return 1
    }

    cat > "$task_dir/task.json" << EOF
{
  "id": "$task_id",
  "description": "$description",
  "owner": "$owner",
  "parent_id": ${parent_id:+\"$parent_id\"}${parent_id:-null},
  "status": "active",
  "branch": "$branch_name",
  "worktree": "$worktree_path",
  "created_at": "$(get_timestamp)"
}
EOF

    echo "$task_id"
}

get_task_worktree() {
    local task_id="$1"
    local task=$(get_task "$task_id")
    echo "$task" | jq -r '.worktree // empty'
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
# Work Items (phase-scoped tasks for parallel coordination)
# ============================================================================

create_work_item() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"
    local description="$3"
    local owner="$4"

    local work_file="$pm_dir/tasks/$task_id/phases/$phase_id/work.jsonl"
    local work_id=$(gen_id "wk")

    local escaped_desc=$(echo "$description" | jq -Rs .)

    echo "{\"id\":\"$work_id\",\"description\":$escaped_desc,\"owner\":\"$owner\",\"status\":\"active\",\"created_at\":\"$(get_timestamp)\"}" >> "$work_file"

    echo "$work_id"
}

get_work_items() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"

    local work_file="$pm_dir/tasks/$task_id/phases/$phase_id/work.jsonl"

    if [[ -f "$work_file" ]]; then
        cat "$work_file"
    fi
}

complete_work_item() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"
    local work_id="$3"

    local work_file="$pm_dir/tasks/$task_id/phases/$phase_id/work.jsonl"

    if [[ ! -f "$work_file" ]]; then
        echo "Error: No work items found" >&2
        return 1
    fi

    # Rewrite file with updated status
    local tmp=$(mktemp)
    while IFS= read -r line; do
        local id=$(echo "$line" | jq -r '.id')
        if [[ "$id" == "$work_id" ]]; then
            echo "$line" | jq -c '.status = "done"'
        else
            echo "$line"
        fi
    done < "$work_file" > "$tmp"
    mv "$tmp" "$work_file"
}

get_agent_work_item() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"
    local agent_name="$3"

    local work_file="$pm_dir/tasks/$task_id/phases/$phase_id/work.jsonl"

    if [[ -f "$work_file" ]]; then
        grep "\"owner\":\"$agent_name\"" "$work_file" | grep '"status":"active"' | head -1
    fi
}

all_work_complete() {
    local pm_dir=$(require_pm_dir)
    local task_id="$1"
    local phase_id="$2"

    local work_file="$pm_dir/tasks/$task_id/phases/$phase_id/work.jsonl"

    # No work items = complete
    if [[ ! -f "$work_file" ]] || [[ ! -s "$work_file" ]]; then
        return 0
    fi

    # Check for any active work items
    if grep -q '"status":"active"' "$work_file"; then
        return 1
    fi

    return 0
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

    # Use worktree if available, otherwise project dir
    local work_dir=$(get_task_worktree "$task_id")
    if [[ -z "$work_dir" ]] || [[ ! -d "$work_dir" ]]; then
        work_dir="$project_dir"
    fi

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
    local log_file="$log_dir/${name}.log"
    (
        cd "$work_dir"
        echo "[$(date)] Agent $name starting (task: $task_id, phase: $phase_id, workdir: $work_dir)" >> "$log_file"
        PM_AGENT_NAME="$name" \
        PM_TASK_ID="$task_id" \
        PM_PHASE_ID="$phase_id" \
        PM_ROLE="$role" \
        PM_CLI="$PM_CLI" \
        claude --dangerously-skip-permissions -p "$prompt" >> "$log_file" 2>&1
        echo "[$(date)] Agent $name exited with code $?" >> "$log_file"
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

    # Use worktree if available, otherwise project dir
    local work_dir=$(get_task_worktree "$task_id")
    if [[ -z "$work_dir" ]] || [[ ! -d "$work_dir" ]]; then
        work_dir="$project_dir"
    fi

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

    # Inject project context if available
    local context_file="$pm_dir/tasks/$task_id/context.md"
    if [[ -f "$context_file" ]]; then
        local context=$(cat "$context_file")
        prompt="## Project Context (from Explore agent)

$context

---

$prompt"
    fi

    # Get phase info
    local phase=$(get_phase "$task_id" "$phase_id")
    local phase_name=$(echo "$phase" | jq -r '.name')
    local phase_limit=$(echo "$phase" | jq -r '.message_limit')
    prompt="${prompt//\{PHASE_NAME\}/$phase_name}"
    prompt="${prompt//\{PHASE_LIMIT\}/$phase_limit}"

    # Spawn Claude Code in background
    local log_file="$log_dir/${name}.log"
    (
        cd "$work_dir"
        echo "[$(date)] Agent $name starting (phase: $phase_id, perspective: $perspective, workdir: $work_dir)" >> "$log_file"
        PM_AGENT_NAME="$name" \
        PM_TASK_ID="$task_id" \
        PM_PHASE_ID="$phase_id" \
        PM_ROLE="$perspective" \
        PM_CLI="$PM_CLI" \
        claude --dangerously-skip-permissions -p "$prompt" >> "$log_file" 2>&1
        echo "[$(date)] Agent $name exited with code $?" >> "$log_file"
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

    # Start dashboard in background on first available port
    local port=3456
    while lsof -i :$port >/dev/null 2>&1; do
        port=$((port + 1))
    done

    local dashboard_dir="$PM_SCRIPT_DIR/dashboard"
    local server="$dashboard_dir/server.py"

    if [[ -f "$server" ]]; then
        nohup python3 "$server" --port "$port" --pm-dir "$PWD/$pm_dir" > "$pm_dir/dashboard.log" 2>&1 &
        echo "$!" > "$pm_dir/dashboard.pid"
        echo ""
        echo "Dashboard: http://localhost:$port"
        echo ""
        echo "Next: pm task \"your task description\""
    fi
}

pm_reset() {
    local pm_dir=$(require_pm_dir)
    local project_dir=$(get_project_dir)

    echo "Resetting plasmodium state..."

    # Kill all agents
    if [[ -f "$pm_dir/agents.json" ]]; then
        local pids=$(jq -r '.agents[].pid // empty' "$pm_dir/agents.json")
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
    fi

    # Remove worktrees and their branches
    if [[ -d "$pm_dir/worktrees" ]]; then
        for worktree in "$pm_dir/worktrees"/*/; do
            if [[ -d "$worktree" ]]; then
                local task_id=$(basename "$worktree")
                local branch_name="task/$task_id"
                git -C "$project_dir" worktree remove "$worktree" --force 2>/dev/null || true
                git -C "$project_dir" branch -D "$branch_name" 2>/dev/null || true
            fi
        done
        rm -rf "$pm_dir/worktrees"
    fi

    # Clear state
    rm -rf "$pm_dir/tasks"
    mkdir -p "$pm_dir/tasks"
    echo '{"agents":{}}' > "$pm_dir/agents.json"
    rm -f "$pm_dir/logs"/*.log

    echo "Reset complete"
}

spawn_explore_agent() {
    local name="$1"
    local task_id="$2"

    local pm_dir=$(require_pm_dir)
    local project_dir=$(get_project_dir)
    local log_dir="$pm_dir/logs"
    mkdir -p "$log_dir"

    # Use worktree if available, otherwise project dir
    local work_dir=$(get_task_worktree "$task_id")
    if [[ -z "$work_dir" ]] || [[ ! -d "$work_dir" ]]; then
        work_dir="$project_dir"
    fi

    local prompt_file="$PM_SCRIPT_DIR/prompts/explore.md"
    if [[ ! -f "$prompt_file" ]]; then
        echo "Error: Explore prompt not found at $prompt_file" >&2
        return 1
    fi

    # Read and substitute prompt
    local prompt=$(cat "$prompt_file")
    prompt="${prompt//\{NAME\}/$name}"
    prompt="${prompt//\{TASK_ID\}/$task_id}"

    # Get task description
    local task=$(get_task "$task_id")
    local task_desc=$(echo "$task" | jq -r '.description')
    prompt="${prompt//\{TASK_DESCRIPTION\}/$task_desc}"

    # Run in foreground (we wait for explore to finish)
    local log_file="$log_dir/${name}.log"
    (
        cd "$work_dir"
        echo "[$(date)] Explore agent $name starting (task: $task_id, workdir: $work_dir)" >> "$log_file"
        PM_AGENT_NAME="$name" \
        PM_TASK_ID="$task_id" \
        PM_ROLE="explore" \
        PM_CLI="$PM_CLI" \
        claude --dangerously-skip-permissions -p "$prompt" >> "$log_file" 2>&1
        local exit_code=$?
        echo "[$(date)] Explore agent $name exited with code $exit_code" >> "$log_file"
        exit $exit_code
    )
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
    echo ""

    # Phase 1: Explore agent maps the project
    local explore_prompt="$PM_SCRIPT_DIR/prompts/explore.md"
    if [[ -f "$explore_prompt" ]]; then
        local explorer=$(gen_agent_name)
        echo "Phase 1: Exploring project structure..."
        echo "Explorer: @$explorer"
        echo ""

        spawn_explore_agent "$explorer" "$task_id"

        # Check if context was written
        local pm_dir=$(get_pm_dir)
        local context_file="$pm_dir/tasks/$task_id/context.md"
        if [[ -f "$context_file" ]]; then
            echo ""
            echo "Project context captured."
        else
            echo ""
            echo "Warning: Explore agent didn't write context.md"
        fi
        echo ""
    fi

    # Phase 2: Owner agent takes over
    local owner_prompt="$PM_SCRIPT_DIR/prompts/owner.md"
    if [[ ! -f "$owner_prompt" ]]; then
        echo "Warning: Owner prompt not found at $owner_prompt" >&2
        echo "Agent not spawned - create the prompt file first" >&2
        return 0
    fi

    echo "Phase 2: Spawning owner agent..."
    spawn_agent "$owner" "$task_id" "$owner_prompt"
    echo ""
    echo "Owner is orchestrating. Monitor: pm status"
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
        # Check if all work items are complete before closing
        if all_work_complete "$task_id" "$phase_id"; then
            close_phase "$task_id" "$phase_id"
            echo "Message posted ($count/$limit) - phase closed"
        else
            echo "Message posted ($count/$limit) - limit reached but waiting for work items"
        fi
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

    # Commit changes in worktree
    local work_dir=$(get_task_worktree "$task_id")
    if [[ -n "$work_dir" ]] && [[ -d "$work_dir" ]]; then
        local task=$(get_task "$task_id")
        local task_desc=$(echo "$task" | jq -r '.description')

        # Stage and commit any changes
        if git -C "$work_dir" status --porcelain | grep -q .; then
            git -C "$work_dir" add -A
            git -C "$work_dir" commit -m "feat: $task_desc

Task: $task_id

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>" 2>/dev/null || true
        fi
    fi

    # Update task status to ready (awaiting merge)
    update_task_status "$task_id" "ready"

    # Unregister self
    unregister_agent "$agent_name"

    echo "Task ready for merge: $task_id"
    echo "Run 'pm merge' to review and merge to main"
}

pm_merge() {
    local pm_dir=$(require_pm_dir)
    local project_dir=$(get_project_dir)

    # Find all ready tasks
    local ready_tasks=()
    for task_dir in "$pm_dir/tasks"/*/; do
        if [[ -f "${task_dir}task.json" ]]; then
            local status=$(jq -r '.status' "${task_dir}task.json")
            if [[ "$status" == "ready" ]]; then
                local task_id=$(jq -r '.id' "${task_dir}task.json")
                ready_tasks+=("$task_id")
            fi
        fi
    done

    if [[ ${#ready_tasks[@]} -eq 0 ]]; then
        echo "No tasks ready for merge."
        echo "Tasks become ready when owner runs 'pm done'"
        return 0
    fi

    echo "Tasks ready for merge: ${#ready_tasks[@]}"
    for t in "${ready_tasks[@]}"; do
        local task=$(get_task "$t")
        local desc=$(echo "$task" | jq -r '.description')
        echo "  - $t: $desc"
    done
    echo ""

    # Build task list for merger prompt
    local task_list=""
    for t in "${ready_tasks[@]}"; do
        local task=$(get_task "$t")
        local desc=$(echo "$task" | jq -r '.description')
        local branch=$(echo "$task" | jq -r '.branch')
        local worktree=$(echo "$task" | jq -r '.worktree')
        task_list+="- **$t**: $desc
  - Branch: \`$branch\`
  - Worktree: \`$worktree\`
"
    done

    # Spawn merger agent
    local merger_name=$(gen_agent_name)
    echo "Spawning merger agent: @$merger_name"

    local prompt_file="$PM_SCRIPT_DIR/prompts/merger.md"
    if [[ ! -f "$prompt_file" ]]; then
        echo "Error: Merger prompt not found at $prompt_file" >&2
        return 1
    fi

    local prompt=$(cat "$prompt_file")
    prompt="${prompt//\{TASK_LIST\}/$task_list}"
    prompt="${prompt//\{PROJECT_DIR\}/$project_dir}"
    prompt="${prompt//\{PM_DIR\}/$pm_dir}"

    local log_dir="$pm_dir/logs"
    mkdir -p "$log_dir"
    local log_file="$log_dir/${merger_name}.log"

    (
        cd "$project_dir"
        echo "[$(date)] Merger agent $merger_name starting" >> "$log_file"
        PM_AGENT_NAME="$merger_name" \
        PM_ROLE="merger" \
        PM_CLI="$PM_CLI" \
        claude --dangerously-skip-permissions -p "$prompt" >> "$log_file" 2>&1
        echo "[$(date)] Merger agent $merger_name exited with code $?" >> "$log_file"
    )
}

pm_resume() {
    local task_id="$1"

    if [[ -z "$task_id" ]]; then
        echo "Usage: pm resume <task-id>" >&2
        exit 1
    fi

    local pm_dir=$(require_pm_dir)
    local task=$(get_task "$task_id")

    if [[ -z "$task" ]]; then
        echo "Error: Task not found: $task_id" >&2
        exit 1
    fi

    local status=$(echo "$task" | jq -r '.status')
    if [[ "$status" != "needs-work" ]]; then
        echo "Error: Task $task_id is not in needs-work status (current: $status)" >&2
        echo "Only tasks sent back by the merger can be resumed" >&2
        exit 1
    fi

    local owner=$(echo "$task" | jq -r '.owner')
    local task_desc=$(echo "$task" | jq -r '.description')

    echo "Resuming task: $task_id"
    echo "Owner: @$owner"

    # Check for feedback
    local feedback_file="$pm_dir/tasks/$task_id/feedback.md"
    if [[ -f "$feedback_file" ]]; then
        echo "Feedback from merger:"
        head -20 "$feedback_file"
        echo "..."
        echo ""
    fi

    # Update status back to active
    update_task_status "$task_id" "active"

    # Spawn owner agent with feedback context
    local owner_prompt="$PM_SCRIPT_DIR/prompts/owner.md"
    if [[ ! -f "$owner_prompt" ]]; then
        echo "Error: Owner prompt not found" >&2
        exit 1
    fi

    local prompt=$(cat "$owner_prompt")
    prompt="${prompt//\{NAME\}/$owner}"
    prompt="${prompt//\{TASK_ID\}/$task_id}"
    prompt="${prompt//\{TASK_DESCRIPTION\}/$task_desc}"

    # Inject feedback if available
    if [[ -f "$feedback_file" ]]; then
        local feedback=$(cat "$feedback_file")
        prompt="## IMPORTANT: Merger Feedback

The merger reviewed your work and sent it back. Address the following:

$feedback

---

$prompt"
    fi

    local work_dir=$(get_task_worktree "$task_id")
    if [[ -z "$work_dir" ]] || [[ ! -d "$work_dir" ]]; then
        work_dir=$(get_project_dir)
    fi

    local log_dir="$pm_dir/logs"
    mkdir -p "$log_dir"
    local log_file="$log_dir/${owner}.log"

    echo "Spawning owner agent..."
    (
        cd "$work_dir"
        echo "[$(date)] Owner $owner resuming (task: $task_id)" >> "$log_file"
        PM_AGENT_NAME="$owner" \
        PM_TASK_ID="$task_id" \
        PM_ROLE="owner" \
        PM_CLI="$PM_CLI" \
        claude --dangerously-skip-permissions -p "$prompt" >> "$log_file" 2>&1
        echo "[$(date)] Owner $owner exited with code $?" >> "$log_file"
    ) &

    local pid=$!
    register_agent "$owner" "$task_id" "" "owner" "$pid"

    echo "$owner (pid: $pid)"
    echo ""
    echo "Owner is addressing merger feedback."
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

pm_work() {
    local description="$1"

    if [[ -z "$description" ]]; then
        echo "Usage: pm work \"description\"" >&2
        echo "  Creates a work item and assigns it to yourself" >&2
        exit 1
    fi

    local task_id=$(get_agent_task)
    local phase_id=$(get_agent_phase)
    local agent_name=$(get_agent_name)

    if [[ -z "$task_id" ]]; then
        echo "Error: pm work can only be called by an agent" >&2
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

    # Check if agent already has active work
    local existing=$(get_agent_work_item "$task_id" "$phase_id" "$agent_name")
    if [[ -n "$existing" ]]; then
        local existing_desc=$(echo "$existing" | jq -r '.description')
        echo "Error: You already have active work: $existing_desc" >&2
        echo "Run 'pm work-done' first" >&2
        exit 1
    fi

    local work_id=$(create_work_item "$task_id" "$phase_id" "$description" "$agent_name")
    echo "Created work item: $work_id"
    echo "Assigned to: @$agent_name"
    echo "Description: $description"

    # Notify the chat
    local role=$(get_agent_role)
    append_message "$task_id" "$phase_id" "$agent_name" "$role" "[WORK] Starting: $description"
}

pm_work_status() {
    local task_id=$(get_agent_task)
    local phase_id=$(get_agent_phase)

    if [[ -z "$task_id" ]]; then
        echo "Error: pm work-status can only be called by an agent" >&2
        exit 1
    fi

    if [[ -z "$phase_id" ]]; then
        local phase=$(get_active_phase "$task_id")
        if [[ -z "$phase" ]]; then
            echo "No active phase"
            return 0
        fi
        phase_id=$(echo "$phase" | jq -r '.id')
    fi

    echo "=== Work Items ==="
    local work_items=$(get_work_items "$task_id" "$phase_id")
    if [[ -z "$work_items" ]]; then
        echo "(none)"
        return 0
    fi

    echo "$work_items" | while IFS= read -r line; do
        local status=$(echo "$line" | jq -r '.status')
        local owner=$(echo "$line" | jq -r '.owner')
        local desc=$(echo "$line" | jq -r '.description')
        local icon="⏳"
        [[ "$status" == "done" ]] && icon="✓"
        echo "$icon @$owner: $desc"
    done
}

pm_work_done() {
    local message="${1:-}"

    local task_id=$(get_agent_task)
    local phase_id=$(get_agent_phase)
    local agent_name=$(get_agent_name)

    if [[ -z "$task_id" ]]; then
        echo "Error: pm work-done can only be called by an agent" >&2
        exit 1
    fi

    if [[ -z "$phase_id" ]]; then
        local phase=$(get_active_phase "$task_id")
        if [[ -z "$phase" ]]; then
            echo "Error: No active phase" >&2
            exit 1
        fi
        phase_id=$(echo "$phase" | jq -r '.id')
    fi

    # Find agent's active work item
    local work_item=$(get_agent_work_item "$task_id" "$phase_id" "$agent_name")
    if [[ -z "$work_item" ]]; then
        echo "Error: You have no active work item" >&2
        exit 1
    fi

    local work_id=$(echo "$work_item" | jq -r '.id')
    local work_desc=$(echo "$work_item" | jq -r '.description')

    complete_work_item "$task_id" "$phase_id" "$work_id"
    echo "Completed: $work_desc"

    # Notify the chat
    local role=$(get_agent_role)
    local notify_msg="[WORK DONE] $work_desc"
    [[ -n "$message" ]] && notify_msg="[WORK DONE] $work_desc - $message"
    append_message "$task_id" "$phase_id" "$agent_name" "$role" "$notify_msg"

    # Check if phase should now close
    local phase=$(get_phase "$task_id" "$phase_id")
    local limit=$(echo "$phase" | jq -r '.message_limit')
    local count=$(get_message_count "$task_id" "$phase_id")

    if [[ $count -ge $limit ]] && all_work_complete "$task_id" "$phase_id"; then
        close_phase "$task_id" "$phase_id"
        echo "All work complete - phase closed"
    fi
}

pm_dashboard() {
    local port="${1:-3456}"
    local pm_dir=$(get_pm_dir)

    if [[ -z "$pm_dir" ]]; then
        echo "Error: Not in a plasmodium project. Run 'pm init' first." >&2
        exit 1
    fi

    local dashboard_dir="$PM_SCRIPT_DIR/dashboard"
    local server="$dashboard_dir/server.py"

    if [[ ! -f "$server" ]]; then
        echo "Error: Dashboard server not found at $server" >&2
        exit 1
    fi

    echo "Starting dashboard..."
    python3 "$server" --port "$port" --pm-dir "$pm_dir"
}

pm_dashboard_stop() {
    local pm_dir=$(get_pm_dir)

    if [[ -z "$pm_dir" ]]; then
        echo "Error: Not in a plasmodium project." >&2
        exit 1
    fi

    # Convert to absolute path for matching
    local abs_pm_dir=$(cd "$(dirname "$pm_dir")" && pwd)/$(basename "$pm_dir")

    # Find dashboard processes for THIS project by matching --pm-dir argument
    local pids=$(ps aux | grep "server.py" | grep -- "--pm-dir" | grep "$abs_pm_dir" | grep -v grep | awk '{print $2}')

    if [[ -z "$pids" ]]; then
        echo "No dashboard running for this project"
        return 0
    fi

    local count=0
    for pid in $pids; do
        if kill "$pid" 2>/dev/null; then
            echo "Stopped dashboard (pid: $pid)"
            ((count++))
        fi
    done

    # Clean up pid file if it exists
    rm -f "$pm_dir/dashboard.pid"

    if [[ $count -eq 0 ]]; then
        echo "No dashboard processes found"
    elif [[ $count -eq 1 ]]; then
        echo "Dashboard stopped"
    else
        echo "Stopped $count dashboard processes"
    fi
}
