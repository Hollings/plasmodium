#!/bin/bash
# Core functions for plasmodium

# Find project root (where .plasmodium lives)
find_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.plasmodium" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Get paths
get_pm_dir() {
    local root=$(find_root) || { echo "Not in a plasmodium project. Run 'pm init'" >&2; exit 1; }
    echo "$root/.plasmodium"
}

get_signal_log() {
    echo "$(get_pm_dir)/signals.log"
}

get_spores_file() {
    echo "$(get_pm_dir)/spores.jsonl"
}

get_workers_file() {
    echo "$(get_pm_dir)/workers.json"
}

# Worker identity
get_worker_name() {
    if [[ -n "${PM_WORKER:-}" ]]; then
        echo "$PM_WORKER"
    else
        echo "human"
    fi
}

# Generate ID
gen_id() {
    # sp-xxxx format
    echo "sp-$(head -c 4 /dev/urandom | xxd -p)"
}

# ============================================
# INIT
# ============================================

pm_init() {
    local dir="${1:-.}"
    local pm_dir="$dir/.plasmodium"

    # Convert to absolute path
    dir="$(cd "$dir" 2>/dev/null && pwd)" || { echo "Directory not found: $1" >&2; exit 1; }
    pm_dir="$dir/.plasmodium"

    mkdir -p "$pm_dir"
    mkdir -p "$pm_dir/logs"
    mkdir -p "$pm_dir/docs"
    mkdir -p "$pm_dir/gates/pre-execute"
    mkdir -p "$pm_dir/gates/pre-fruit"
    mkdir -p "$pm_dir/gates/post-fruit"

    # Initialize signal log
    if [[ ! -f "$pm_dir/signals.log" ]]; then
        echo "# Plasmodium Signal Log" > "$pm_dir/signals.log"
        echo "# Workers communicate here" >> "$pm_dir/signals.log"
        echo "---" >> "$pm_dir/signals.log"
    fi

    # Initialize spores file
    if [[ ! -f "$pm_dir/spores.jsonl" ]]; then
        touch "$pm_dir/spores.jsonl"
    fi

    # Initialize workers file
    if [[ ! -f "$pm_dir/workers.json" ]]; then
        echo '{"workers": {}}' > "$pm_dir/workers.json"
    fi

    # Copy dashboard files from plasmodium source
    if [[ -f "$PM_SCRIPT_DIR/dashboard/index.html" ]]; then
        cp "$PM_SCRIPT_DIR/dashboard/index.html" "$pm_dir/index.html"
        cp "$PM_SCRIPT_DIR/dashboard/server.py" "$pm_dir/server.py"
    fi

    # Save config with pm path for server.py to use
    echo "{\"pm_cli\": \"$PM_SCRIPT_DIR/pm\"}" > "$pm_dir/config.json"

    echo "Initialized plasmodium in $pm_dir/"
    echo ""
    echo "Next steps:"
    echo "  cd $dir"
    echo "  pm dashboard     # start the dashboard"
    echo "  pm new \"task\"    # create work"
}

pm_dashboard() {
    local pm_dir=$(get_pm_dir)
    local background=false
    local port="3456"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--background) background=true; shift ;;
            *) port="$1"; shift ;;
        esac
    done

    if [[ ! -f "$pm_dir/server.py" ]]; then
        echo "Dashboard not found. Run 'pm init' first." >&2
        exit 1
    fi

    cd "$pm_dir"
    if [[ "$background" == "true" ]]; then
        python3 server.py "$port" > /dev/null 2>&1 &
        local pid=$!
        sleep 0.5  # let it find a port and write file
        if [[ -f ".dashboard_port" ]]; then
            local actual_port=$(cat .dashboard_port)
            echo "Dashboard: http://localhost:$actual_port (PID: $pid)"
            open "http://localhost:$actual_port" 2>/dev/null || true
        else
            echo "Dashboard starting... (PID: $pid)"
        fi
    else
        python3 server.py "$port"
    fi
}

pm_reset() {
    local pm_dir=$(get_pm_dir)

    echo "Resetting plasmodium state..."

    # Clear spores
    > "$pm_dir/spores.jsonl"

    # Clear workers
    echo '{"workers": {}}' > "$pm_dir/workers.json"

    # Reset signals log
    cat > "$pm_dir/signals.log" << 'EOF'
# Plasmodium Signal Log
# Workers communicate here
---
EOF

    # Clear docs
    rm -rf "$pm_dir/docs"/*

    # Clear logs
    rm -f "$pm_dir/logs"/*.log

    echo "Reset complete. Run 'pm status' to verify."
}

# ============================================
# SIGNALS
# ============================================

pm_signal() {
    local spore=""
    local msg=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --spore|-s)
                spore="$2"
                shift 2
                ;;
            *)
                if [[ -z "$msg" ]]; then
                    msg="$1"
                else
                    msg="$msg $1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$msg" ]]; then
        echo "Usage: pm signal [--spore <id>] <message>" >&2
        exit 1
    fi

    local log=$(get_signal_log)
    local worker=$(get_worker_name)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -n "$spore" ]]; then
        echo "[$timestamp] @$worker [$spore]: $msg" >> "$log"
    else
        echo "[$timestamp] @$worker: $msg" >> "$log"
    fi
    echo "signaled"
}

pm_signals() {
    local log=$(get_signal_log)
    local follow=false
    local spore=""
    local n="50"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --follow|-f) follow=true; shift ;;
            --spore|-s) spore="$2"; shift 2 ;;
            *) n="$1"; shift ;;
        esac
    done

    if [[ "$follow" == "true" ]]; then
        if [[ -n "$spore" ]]; then
            tail -f "$log" | grep --line-buffered "\[$spore\]"
        else
            tail -f "$log"
        fi
    else
        if [[ -n "$spore" ]]; then
            grep "\[$spore\]" "$log" | tail -n "$n"
        else
            tail -n "$n" "$log"
        fi
    fi
}

# ============================================
# SPORE MANAGEMENT
# ============================================

pm_new() {
    local depends_on=()
    local task=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depends)
                shift
                depends_on+=("$1")
                shift
                ;;
            *)
                if [[ -z "$task" ]]; then
                    task="$1"
                else
                    task="$task $1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$task" ]]; then
        echo "Usage: pm new [--depends <spore-id>]... <task description>" >&2
        exit 1
    fi

    local id=$(gen_id)
    local spores=$(get_spores_file)
    local worker=$(get_worker_name)
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    # Determine initial status based on dependencies
    local status="raw"
    if [[ ${#depends_on[@]} -gt 0 ]]; then
        # Check if all dependencies are already done
        local all_done=true
        for dep_id in "${depends_on[@]}"; do
            local dep_spore=$(get_spore "$dep_id")
            if [[ -n "$dep_spore" ]]; then
                local dep_status=$(echo "$dep_spore" | jq -r '.status')
                if [[ "$dep_status" != "done" ]]; then
                    all_done=false
                    break
                fi
            else
                # Dependency doesn't exist yet - block
                all_done=false
                break
            fi
        done
        if ! $all_done; then
            status="blocked"
        fi
    fi

    local depends_json=$(printf '%s\n' "${depends_on[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")

    local spore=$(jq -nc \
        --arg id "$id" \
        --arg task "$task" \
        --arg created "$timestamp" \
        --arg creator "$worker" \
        --arg status "$status" \
        --argjson depends "$depends_json" \
        '{
            id: $id,
            type: "task",
            parent: null,
            children: [],
            depends_on: $depends,
            status: $status,
            phase: null,
            task: $task,
            claimed_by: null,
            fruit: null,
            plan_file: null,
            approvals_needed: 0,
            approvals: [],
            rejections: [],
            created: $created,
            creator: $creator
        }')

    echo "$spore" >> "$spores"

    if [[ ${#depends_on[@]} -gt 0 ]]; then
        if [[ "$status" == "blocked" ]]; then
            pm_signal "created spore $id (blocked by ${depends_on[*]}): $task"
        else
            pm_signal "created spore $id (depends on ${depends_on[*]}, ready): $task"
        fi
    else
        pm_signal "created spore $id: $task"
    fi

    # Auto-spawn: if human creates a non-blocked spore, spawn a worker
    if [[ "$worker" == "human" && "$status" != "blocked" ]]; then
        spawn_workers_background 1
    fi

    echo "$id"
}

get_spore() {
    local id="$1"
    local spores=$(get_spores_file)
    grep "\"id\":\"$id\"" "$spores" | tail -1
}

update_spore() {
    local id="$1"
    local field="$2"
    local value="$3"

    local spores=$(get_spores_file)
    local spore=$(get_spore "$id")

    if [[ -z "$spore" ]]; then
        echo "Spore not found: $id" >&2
        exit 1
    fi

    # Update the spore and append new version
    local updated=$(echo "$spore" | jq -c --arg v "$value" ".$field = \$v")
    echo "$updated" >> "$spores"
}

update_spore_json() {
    local id="$1"
    local field="$2"
    local json_value="$3"

    local spores=$(get_spores_file)
    local spore=$(get_spore "$id")

    if [[ -z "$spore" ]]; then
        echo "Spore not found: $id" >&2
        exit 1
    fi

    local updated=$(echo "$spore" | jq -c --argjson v "$json_value" ".$field = \$v")
    echo "$updated" >> "$spores"
}

pm_claim() {
    local id="$1"
    if [[ -z "$id" ]]; then
        echo "Usage: pm claim <spore-id>" >&2
        exit 1
    fi

    local worker=$(get_worker_name)
    update_spore "$id" "claimed_by" "$worker"
    pm_signal "claimed $id"
    echo "claimed $id"
}

pm_explore() {
    local id="$1"
    if [[ -z "$id" ]]; then
        echo "Usage: pm explore <spore-id>" >&2
        exit 1
    fi

    local spores=$(get_spores_file)
    local spore=$(get_spore "$id")
    local updated=$(echo "$spore" | jq -c '.status = "exploring" | .phase = "plasmodium"')
    echo "$updated" >> "$spores"

    pm_signal "exploring $id (plasmodium mode)"
    echo "exploring $id"
}

pm_execute() {
    local id="$1"
    if [[ -z "$id" ]]; then
        echo "Usage: pm execute <spore-id>" >&2
        exit 1
    fi

    local spores=$(get_spores_file)
    local spore=$(get_spore "$id")
    local updated=$(echo "$spore" | jq -c '.status = "executing" | .phase = "mycelium"')
    echo "$updated" >> "$spores"

    pm_signal "executing $id (mycelium mode)"
    echo "executing $id"
}

pm_split() {
    local parent_id="$1"
    shift

    if [[ -z "$parent_id" ]]; then
        echo "Usage: pm split <parent-id> <child1> <child2> ..." >&2
        exit 1
    fi

    local children=()

    for task in "$@"; do
        local child_id=$(gen_id)
        local spores=$(get_spores_file)
        local worker=$(get_worker_name)
        local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

        local spore=$(jq -nc \
            --arg id "$child_id" \
            --arg parent "$parent_id" \
            --arg task "$task" \
            --arg created "$timestamp" \
            --arg creator "$worker" \
            '{
                id: $id,
                parent: $parent,
                children: [],
                status: "raw",
                phase: null,
                task: $task,
                claimed_by: null,
                fruit: null,
                created: $created,
                creator: $creator
            }')

        echo "$spore" >> "$spores"
        children+=("$child_id")
        echo "created child: $child_id - $task"
    done

    # Update parent with children
    local children_json=$(printf '%s\n' "${children[@]}" | jq -R . | jq -s .)
    update_spore_json "$parent_id" "children" "$children_json"
    update_spore "$parent_id" "status" "waiting"

    pm_signal "split $parent_id into ${#children[@]} children"
}

pm_fruit() {
    local id="$1"
    shift
    local output="$*"

    if [[ -z "$id" ]]; then
        echo "Usage: pm fruit <spore-id> <output description>" >&2
        exit 1
    fi

    # Run pre-fruit gates
    run_gates "pre-fruit" "$id" || { echo "gates failed" >&2; return 1; }

    local spores=$(get_spores_file)
    local spore=$(get_spore "$id")
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    local updated=$(echo "$spore" | jq -c \
        --arg fruit "$output" \
        --arg time "$timestamp" \
        '.status = "done" | .phase = null | .fruit = $fruit | .completed = $time')
    echo "$updated" >> "$spores"

    pm_signal "fruited $id: $output"

    # Check if parent can ripen
    local parent=$(echo "$spore" | jq -r '.parent // empty')
    if [[ -n "$parent" ]]; then
        pm_ripen "$parent" 2>/dev/null || true
    fi

    # Unblock any spores that depend on this one
    unblock_dependents "$id"

    # Run post-fruit gates
    run_gates "post-fruit" "$id" || true

    echo "fruited $id"
}

# Unblock spores that were waiting on this one
unblock_dependents() {
    local completed_id="$1"
    local spores=$(get_spores_file)

    # Find all blocked spores that depend on completed_id
    jq -rsc --arg dep "$completed_id" '
        group_by(.id) | map(last) | .[] |
        select(.status == "blocked" and (.depends_on | index($dep)))
    ' "$spores" 2>/dev/null | while read -r spore; do
        [[ -z "$spore" ]] && continue

        local blocked_id=$(echo "$spore" | jq -r '.id')
        local depends=$(echo "$spore" | jq -r '.depends_on[]' 2>/dev/null)

        # Check if ALL dependencies are now done
        local all_done=true
        for dep_id in $depends; do
            local dep_spore=$(get_spore "$dep_id")
            local dep_status=$(echo "$dep_spore" | jq -r '.status')
            if [[ "$dep_status" != "done" ]]; then
                all_done=false
                break
            fi
        done

        if $all_done; then
            update_spore "$blocked_id" "status" "raw"
            pm_signal "$blocked_id unblocked (dependencies complete)"
        fi
    done
}

pm_ripen() {
    local id="$1"
    if [[ -z "$id" ]]; then
        echo "Usage: pm ripen <spore-id>" >&2
        exit 1
    fi

    local spore=$(get_spore "$id")
    local children=$(echo "$spore" | jq -r '.children[]' 2>/dev/null)

    if [[ -z "$children" ]]; then
        echo "no children to ripen"
        return 0
    fi

    # Check if all children are done
    local all_done=true
    for child_id in $children; do
        local child=$(get_spore "$child_id")
        local status=$(echo "$child" | jq -r '.status')
        if [[ "$status" != "done" ]]; then
            all_done=false
            break
        fi
    done

    if $all_done; then
        update_spore "$id" "status" "ripe"
        pm_signal "$id ripened - all children complete"
        echo "$id is ripe!"
    else
        echo "$id not ready - children still in progress"
    fi
}

# ============================================
# WORKERS
# ============================================

# Generate a unique worker name
gen_worker_name() {
    local trees=("oak" "maple" "birch" "willow" "cedar" "pine" "ash" "elm" "beech" "hazel")
    echo "${trees[$RANDOM % ${#trees[@]}]}_$(head -c 2 /dev/urandom | xxd -p)"
}

# Internal: spawn a worker (can be foreground or background)
_spawn_worker() {
    local name="$1"
    local background="${2:-false}"

    local pm_dir=$(get_pm_dir)
    local project_root=$(find_root)
    local prompt_file="$PM_SCRIPT_DIR/prompts/worker.txt"

    if [[ ! -f "$prompt_file" ]]; then
        echo "Worker prompt not found: $prompt_file" >&2
        return 1
    fi

    # Full path to pm CLI
    local pm_cli="$PM_SCRIPT_DIR/pm"

    # Build the prompt with substitutions
    local prompt=$(cat "$prompt_file" | sed \
        -e "s|{WORKER}|$name|g" \
        -e "s|{PROJECT}|$project_root|g" \
        -e "s|{PM_DIR}|$pm_dir|g" \
        -e "s|{PM_CLI}|$pm_cli|g")

    pm_signal "spawning worker @$name"

    # Record worker
    local workers=$(get_workers_file)
    local tmp=$(mktemp)
    jq --arg name "$name" --arg time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '.workers[$name] = {started: $time, status: "active"}' \
        "$workers" > "$tmp" && mv "$tmp" "$workers"

    if [[ "$background" == "true" ]]; then
        # Run in background, redirect output to log
        local log_dir="$pm_dir/logs"
        mkdir -p "$log_dir"
        (
            cd "$project_root"
            PM_WORKER="$name" claude -p "$prompt" \
                --model opus \
                --dangerously-skip-permissions \
                > "$log_dir/$name.log" 2>&1
        ) &
        echo "spawned @$name (pid $!)"
    else
        echo "Spawning worker: @$name"
        echo "---"
        cd "$project_root"
        PM_WORKER="$name" exec claude -p "$prompt" \
            --model opus \
            --dangerously-skip-permissions
    fi
}

# Spawn worker(s) in background - used by hooks
spawn_workers_background() {
    local count="${1:-1}"
    for ((i=0; i<count; i++)); do
        local name=$(gen_worker_name)
        _spawn_worker "$name" true
    done
}

pm_spawn() {
    local name="${1:-$(gen_worker_name)}"
    _spawn_worker "$name" false
}

pm_status() {
    local pm_dir=$(get_pm_dir)
    local spores=$(get_spores_file)
    local workers=$(get_workers_file)

    echo "=== PLASMODIUM STATUS ==="
    echo ""

    echo "WORKERS:"
    jq -r '.workers | to_entries[] | "  @\(.key): \(.value.status) (since \(.value.started))"' "$workers" 2>/dev/null || echo "  (none)"
    echo ""

    echo "SPORES:"
    if [[ -s "$spores" ]]; then
        # Use jq to get unique spores (last occurrence wins)
        jq -rs 'group_by(.id) | map(last) | .[] | "\(.id)\t\(.status)\t\(.claimed_by // "-")\t\(.task)"' "$spores" 2>/dev/null | \
        while IFS=$'\t' read -r id status claimed task; do
            # Remove quotes from jq output
            id=${id//\"/}
            status=${status//\"/}
            claimed=${claimed//\"/}
            task=${task//\"/}
            printf "  %-12s %-10s @%-10s %s\n" "$id" "[$status]" "$claimed" "${task:0:50}"
        done | head -20
        [[ ${PIPESTATUS[0]} -ne 0 ]] && echo "  (error reading spores)"
    else
        echo "  (none)"
    fi
    echo ""

    echo "RECENT SIGNALS:"
    tail -5 "$(get_signal_log)" | grep -v "^#" | grep -v "^---"
}

# ============================================
# GATES (HOOKS)
# ============================================

run_gates() {
    local phase="$1"  # pre-execute, pre-fruit, post-fruit
    local spore_id="$2"

    local pm_dir=$(get_pm_dir)
    local gates_dir="$pm_dir/gates/$phase"

    if [[ ! -d "$gates_dir" ]]; then
        return 0  # No gates for this phase
    fi

    for gate in "$gates_dir"/*.sh; do
        [[ -f "$gate" ]] || continue
        local gate_name=$(basename "$gate")

        if ! bash "$gate" "$spore_id" 2>&1; then
            pm_signal "GATE FAILED: $gate_name for $spore_id"
            return 1
        fi
    done

    return 0
}

# ============================================
# PLAN & APPROVAL
# ============================================

get_docs_dir() {
    echo "$(get_pm_dir)/docs"
}

pm_plan() {
    local approvals=1
    local spore_id=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --approvals)
                shift
                approvals="$1"
                shift
                ;;
            *)
                spore_id="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$spore_id" ]]; then
        echo "Usage: pm plan <spore-id> [--approvals N]" >&2
        exit 1
    fi

    local spore=$(get_spore "$spore_id")
    if [[ -z "$spore" ]]; then
        echo "Spore not found: $spore_id" >&2
        exit 1
    fi

    local docs_dir=$(get_docs_dir)
    local spore_docs="$docs_dir/$spore_id"
    local plan_file="$spore_docs/plan.md"

    # Create docs directory
    mkdir -p "$spore_docs"

    # Create plan template if it doesn't exist
    if [[ ! -f "$plan_file" ]]; then
        local task=$(echo "$spore" | jq -r '.task')
        cat > "$plan_file" << EOF
# Plan for $spore_id

## Task
$task

## Approach
[Describe your approach here]

## Changes
[List the files/components you'll modify]

## Risks
[Any risks or concerns]

## Testing
[How will you verify this works]
EOF
        echo "Created plan template: $plan_file"
        echo "Edit the plan, then run: pm plan $spore_id --approvals $approvals"
        return 0
    fi

    # Update spore with plan info and create review spore
    local spores=$(get_spores_file)
    local updated=$(echo "$spore" | jq -c \
        --arg plan "docs/$spore_id/plan.md" \
        --argjson approvals "$approvals" \
        '.plan_file = $plan | .approvals_needed = $approvals | .status = "pending_approval"')
    echo "$updated" >> "$spores"

    # Create review spore
    local review_id=$(gen_id)
    local worker=$(get_worker_name)
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local task=$(echo "$spore" | jq -r '.task')

    local review=$(jq -nc \
        --arg id "$review_id" \
        --arg reviews "$spore_id" \
        --arg task "review plan for $spore_id: $task" \
        --arg created "$timestamp" \
        --arg creator "$worker" \
        '{
            id: $id,
            type: "review",
            reviews: $reviews,
            parent: null,
            children: [],
            depends_on: [],
            status: "raw",
            phase: null,
            task: $task,
            claimed_by: null,
            fruit: null,
            plan_file: null,
            approvals_needed: 0,
            approvals: [],
            rejections: [],
            created: $created,
            creator: $creator
        }')
    echo "$review" >> "$spores"

    pm_signal "PLAN for $spore_id needs $approvals approval(s). Review: $review_id. Plan: $plan_file"

    # Auto-spawn: spawn N workers to ensure reviewers exist
    spawn_workers_background "$approvals"

    echo "Plan submitted. Review spore: $review_id"
    echo "Waiting for $approvals approval(s)"
}

pm_approve() {
    local spore_id="$1"
    shift
    local reason="$*"

    if [[ -z "$spore_id" ]]; then
        echo "Usage: pm approve <spore-id> [reason]" >&2
        exit 1
    fi

    local spore=$(get_spore "$spore_id")
    if [[ -z "$spore" ]]; then
        echo "Spore not found: $spore_id" >&2
        exit 1
    fi

    local worker=$(get_worker_name)
    local spores=$(get_spores_file)

    # Add approval
    local current_approvals=$(echo "$spore" | jq -r '.approvals | length')
    local needed=$(echo "$spore" | jq -r '.approvals_needed')

    local updated=$(echo "$spore" | jq -c --arg w "$worker" '.approvals += [$w]')
    echo "$updated" >> "$spores"

    local new_count=$((current_approvals + 1))
    pm_signal "APPROVED $spore_id ($new_count/$needed): $reason"

    # Check if we have enough approvals
    if [[ $new_count -ge $needed ]]; then
        update_spore "$spore_id" "status" "approved"
        pm_signal "$spore_id fully approved - ready to execute"
    fi

    # Find and fruit the review spore
    local review_spore=$(jq -rsc --arg reviews "$spore_id" '
        group_by(.id) | map(last) | .[] |
        select(.type == "review" and .reviews == $reviews and .status != "done")
    ' "$spores" | head -1)

    if [[ -n "$review_spore" ]]; then
        local review_id=$(echo "$review_spore" | jq -r '.id')
        # Mark review as claimed by this worker and fruit it
        update_spore "$review_id" "claimed_by" "$worker"
        local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
        local review_updated=$(echo "$review_spore" | jq -c \
            --arg fruit "approved by @$worker: $reason" \
            --arg time "$timestamp" \
            --arg claimed "$worker" \
            '.status = "done" | .phase = null | .fruit = $fruit | .completed = $time | .claimed_by = $claimed')
        echo "$review_updated" >> "$spores"
    fi

    echo "approved $spore_id"
}

pm_reject() {
    local spore_id="$1"
    shift
    local reason="$*"

    if [[ -z "$spore_id" ]]; then
        echo "Usage: pm reject <spore-id> <reason>" >&2
        exit 1
    fi

    if [[ -z "$reason" ]]; then
        echo "Rejection reason required" >&2
        exit 1
    fi

    local spore=$(get_spore "$spore_id")
    if [[ -z "$spore" ]]; then
        echo "Spore not found: $spore_id" >&2
        exit 1
    fi

    local worker=$(get_worker_name)
    local spores=$(get_spores_file)

    # Add rejection
    local rejection=$(jq -nc --arg w "$worker" --arg r "$reason" '{worker: $w, reason: $r}')
    local updated=$(echo "$spore" | jq -c --argjson rej "$rejection" '.rejections += [$rej] | .status = "rejected"')
    echo "$updated" >> "$spores"

    pm_signal "REJECTED $spore_id by @$worker: $reason"
    echo "rejected $spore_id - author must revise plan"
}
