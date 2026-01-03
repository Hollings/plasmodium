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
    mkdir -p "$dir/.plasmodium"

    # Initialize signal log
    if [[ ! -f "$dir/.plasmodium/signals.log" ]]; then
        echo "# Plasmodium Signal Log" > "$dir/.plasmodium/signals.log"
        echo "# Workers communicate here" >> "$dir/.plasmodium/signals.log"
        echo "---" >> "$dir/.plasmodium/signals.log"
    fi

    # Initialize spores file
    if [[ ! -f "$dir/.plasmodium/spores.jsonl" ]]; then
        touch "$dir/.plasmodium/spores.jsonl"
    fi

    # Initialize workers file
    if [[ ! -f "$dir/.plasmodium/workers.json" ]]; then
        echo '{"workers": {}}' > "$dir/.plasmodium/workers.json"
    fi

    echo "Initialized plasmodium in $dir/.plasmodium/"
}

# ============================================
# SIGNALS
# ============================================

pm_signal() {
    local msg="$*"
    if [[ -z "$msg" ]]; then
        echo "Usage: pm signal <message>" >&2
        exit 1
    fi

    local log=$(get_signal_log)
    local worker=$(get_worker_name)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] @$worker: $msg" >> "$log"
    echo "signaled"
}

pm_signals() {
    local log=$(get_signal_log)

    if [[ "$1" == "--follow" || "$1" == "-f" ]]; then
        tail -f "$log"
    else
        # Show last 20 by default
        local n="${1:-20}"
        tail -n "$n" "$log"
    fi
}

# ============================================
# SPORE MANAGEMENT
# ============================================

pm_new() {
    local task="$*"
    if [[ -z "$task" ]]; then
        echo "Usage: pm new <task description>" >&2
        exit 1
    fi

    local id=$(gen_id)
    local spores=$(get_spores_file)
    local worker=$(get_worker_name)
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    local spore=$(jq -nc \
        --arg id "$id" \
        --arg task "$task" \
        --arg created "$timestamp" \
        --arg creator "$worker" \
        '{
            id: $id,
            parent: null,
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
    pm_signal "created spore $id: $task"
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

    echo "fruited $id"
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

pm_spawn() {
    local name="${1:-}"

    # Generate name if not provided (tree names)
    if [[ -z "$name" ]]; then
        local trees=("oak" "maple" "birch" "willow" "cedar" "pine" "ash" "elm" "beech" "hazel")
        name="${trees[$RANDOM % ${#trees[@]}]}_$$"
    fi

    local pm_dir=$(get_pm_dir)
    local project_root=$(find_root)
    local prompt_file="$PM_SCRIPT_DIR/prompts/worker.txt"

    if [[ ! -f "$prompt_file" ]]; then
        echo "Worker prompt not found: $prompt_file" >&2
        exit 1
    fi

    # Build the prompt with substitutions
    local prompt=$(cat "$prompt_file" | sed \
        -e "s|{WORKER}|$name|g" \
        -e "s|{PROJECT}|$project_root|g" \
        -e "s|{PM_DIR}|$pm_dir|g")

    pm_signal "spawning worker @$name"

    # Record worker
    local workers=$(get_workers_file)
    local tmp=$(mktemp)
    jq --arg name "$name" --arg time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '.workers[$name] = {started: $time, status: "active"}' \
        "$workers" > "$tmp" && mv "$tmp" "$workers"

    echo "Spawning worker: @$name"
    echo "---"

    # Run claude code headless with worker identity
    cd "$project_root"
    PM_WORKER="$name" exec claude -p "$prompt" \
        --model opus \
        --permission-mode acceptEdits
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
