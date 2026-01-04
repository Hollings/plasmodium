#!/bin/bash
# Plasmodium v2 - Multi-agent collaboration through bounded discussion phases
# "The room where it happens"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PM_SCRIPT_DIR="$SCRIPT_DIR"
export PM_CLI="$SCRIPT_DIR/pm"

source "$SCRIPT_DIR/lib/core.sh"

case "${1:-}" in
    # Setup
    init)
        shift
        pm_init "$@"
        ;;
    reset)
        shift
        pm_reset "$@"
        ;;
    clean)
        shift
        pm_clean "$@"
        ;;

    # Task management (human)
    task)
        shift
        pm_task "$@"
        ;;
    status)
        shift
        pm_status "$@"
        ;;
    kill)
        shift
        pm_kill "$@"
        ;;

    # Phase management (owner)
    phase)
        shift
        pm_phase "$@"
        ;;
    extend-phase)
        shift
        pm_extend_phase "$@"
        ;;
    end-phase)
        shift
        pm_end_phase "$@"
        ;;

    # Discussion (all agents)
    chat)
        shift
        pm_chat "$@"
        ;;
    say)
        shift
        pm_say "$@"
        ;;
    history)
        shift
        pm_history "$@"
        ;;

    # Work coordination (phase agents)
    work)
        shift
        pm_work "$@"
        ;;
    work-status)
        shift
        pm_work_status "$@"
        ;;
    work-done)
        shift
        pm_work_done "$@"
        ;;

    # Task lifecycle (owner)
    subtask)
        shift
        pm_subtask "$@"
        ;;
    wait-children)
        shift
        pm_wait_children "$@"
        ;;
    done)
        shift
        pm_done "$@"
        ;;

    # Dashboard
    dashboard)
        shift
        pm_dashboard "$@"
        ;;
    dashboard-stop)
        shift
        pm_dashboard_stop "$@"
        ;;

    # Merge
    merge)
        shift
        pm_merge "$@"
        ;;
    resume)
        shift
        pm_resume "$@"
        ;;

    # Help
    -h|--help|help|"")
        echo "plasmodium v2 - multi-agent collaboration"
        echo ""
        echo "Usage: pm <command> [args...]"
        echo ""
        echo "Setup:"
        echo "  init                      Initialize (auto-starts dashboard)"
        echo "  reset                     Clear all state"
        echo "  clean                     Remove dead agents from registry"
        echo "  dashboard [port]          Start dashboard (foreground)"
        echo "  dashboard-stop            Stop dashboard for this project"
        echo ""
        echo "For Humans:"
        echo "  task \"description\"        Create task, spawn owner agent"
        echo "  status                    Show tasks, phases, agents"
        echo "  kill <task-id>            Kill task and its agents"
        echo ""
        echo "For All Agents:"
        echo "  chat                      Read current phase messages"
        echo "  say \"message\"             Post to current phase"
        echo "  work \"description\"        Claim a work item (announces to chat)"
        echo "  work-status               Show all work items in phase"
        echo "  work-done [\"message\"]     Complete your work item"
        echo "  history --tail N          Read previous phase discussions"
        echo ""
        echo "For Owner Agents:"
        echo "  phase \"Topic\" --limit N \"perspective 1\" \"perspective 2\""
        echo "                            Create discussion with custom perspectives"
        echo "  extend-phase N            Add N more messages to limit"
        echo "  end-phase                 Close phase early"
        echo "  subtask \"description\"     Create child task"
        echo "  wait-children             Block until subtasks done"
        echo "  done                      Mark task ready for merge"
        echo ""
        echo "Merge Workflow:"
        echo "  merge                     Spawn merger agent to review ready tasks"
        echo "  resume <task-id>          Resume a task that needs work"
        ;;

    *)
        echo "Unknown command: $1" >&2
        echo "Run 'pm --help' for usage" >&2
        exit 1
        ;;
esac
