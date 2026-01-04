#!/usr/bin/env python3
"""
Plasmodium Dashboard Server

Simple HTTP server that serves the dashboard and provides API endpoints
for reading task/phase/agent data from .plasmodium directory.

Endpoints:
- GET /              -> serves index.html
- GET /api/overview  -> all tasks, phases, agents
- GET /api/messages?phase_id=ph-xxx -> messages for a specific phase
"""

import json
import os
import re
import signal
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

PLASMODIUM_DIR = Path(".plasmodium")
SCRIPT_DIR = Path(__file__).parent.absolute()

# Phase IDs should match this pattern (e.g., ph-abc123)
PHASE_ID_PATTERN = re.compile(r'^ph-[a-f0-9]+$')


def is_process_alive(pid: int) -> bool:
    """Check if a process with given PID is running."""
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def load_json_file(path: Path) -> dict | list | None:
    """Load JSON from file, return None if missing or invalid."""
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def load_jsonl_file(path: Path) -> list[dict]:
    """Load JSONL file (one JSON object per line)."""
    messages = []
    try:
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        messages.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except FileNotFoundError:
        pass
    return messages


def get_overview() -> dict:
    """
    Build complete overview of all tasks, phases, and agents.
    Returns structure suitable for dashboard rendering.
    """
    result = {
        "tasks": [],
        "agents": [],
    }

    # Load agents
    agents_data = load_json_file(PLASMODIUM_DIR / "agents.json")
    if agents_data and "agents" in agents_data:
        for name, agent in agents_data["agents"].items():
            agent_info = {
                "name": name,
                "task_id": agent.get("task_id"),
                "phase_id": agent.get("phase_id"),
                "role": agent.get("role"),
                "pid": agent.get("pid"),
                "alive": is_process_alive(agent.get("pid")),
                "registered_at": agent.get("registered_at"),
            }
            result["agents"].append(agent_info)

    # Load tasks
    tasks_dir = PLASMODIUM_DIR / "tasks"
    if tasks_dir.exists():
        for task_dir in tasks_dir.iterdir():
            if not task_dir.is_dir():
                continue

            task_data = load_json_file(task_dir / "task.json")
            if not task_data:
                continue

            task_info = {
                "id": task_data.get("id"),
                "description": task_data.get("description"),
                "owner": task_data.get("owner"),
                "status": task_data.get("status"),
                "created_at": task_data.get("created_at"),
                "phases": [],
            }

            # Load phases for this task
            phases_dir = task_dir / "phases"
            if phases_dir.exists():
                for phase_dir in phases_dir.iterdir():
                    if not phase_dir.is_dir():
                        continue

                    phase_data = load_json_file(phase_dir / "phase.json")
                    if not phase_data:
                        continue

                    # Count messages
                    messages = load_jsonl_file(phase_dir / "messages.jsonl")
                    message_count = len(messages)

                    phase_info = {
                        "id": phase_data.get("id"),
                        "task_id": phase_data.get("task_id"),
                        "name": phase_data.get("name"),
                        "status": phase_data.get("status"),
                        "message_limit": phase_data.get("message_limit"),
                        "message_count": message_count,
                        "roles": phase_data.get("roles", []),
                        "created_at": phase_data.get("created_at"),
                    }
                    task_info["phases"].append(phase_info)

                # Sort phases by created_at
                task_info["phases"].sort(key=lambda p: p.get("created_at", ""))

            result["tasks"].append(task_info)

    # Sort tasks by created_at (newest first)
    result["tasks"].sort(key=lambda t: t.get("created_at", ""), reverse=True)

    return result


def get_messages(phase_id: str) -> dict:
    """
    Get all messages for a specific phase.
    """
    result = {
        "phase_id": phase_id,
        "messages": [],
        "error": None,
    }

    # Validate phase_id format to prevent path traversal
    if not PHASE_ID_PATTERN.match(phase_id):
        result["error"] = "Invalid phase_id format"
        return result

    # Find the phase directory
    tasks_dir = PLASMODIUM_DIR / "tasks"
    if not tasks_dir.exists():
        result["error"] = "No tasks directory"
        return result

    # Search all tasks for this phase
    for task_dir in tasks_dir.iterdir():
        if not task_dir.is_dir():
            continue

        phase_dir = task_dir / "phases" / phase_id
        if phase_dir.exists():
            messages = load_jsonl_file(phase_dir / "messages.jsonl")
            result["messages"] = messages
            return result

    result["error"] = f"Phase {phase_id} not found"
    return result


class DashboardHandler(SimpleHTTPRequestHandler):
    """HTTP request handler for the dashboard."""

    def log_message(self, format, *args):
        """Suppress default logging."""
        pass

    def send_json(self, data: dict, status: int = 200):
        """Send JSON response."""
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/overview":
            try:
                data = get_overview()
                self.send_json(data)
            except Exception as e:
                self.send_json({"error": str(e)}, 500)

        elif path == "/api/messages":
            query = parse_qs(parsed.query)
            phase_id = query.get("phase_id", [None])[0]

            if not phase_id:
                self.send_json({"error": "phase_id query param required"}, 400)
                return

            try:
                data = get_messages(phase_id)
                self.send_json(data)
            except Exception as e:
                self.send_json({"error": str(e)}, 500)

        elif path == "/" or path == "/index.html":
            # Serve index.html
            try:
                with open("index.html", "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", len(content))
                self.end_headers()
                self.wfile.write(content)
            except FileNotFoundError:
                self.send_response(404)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"index.html not found")

        else:
            # Serve static files
            super().do_GET()


def main():
    import sys
    global PLASMODIUM_DIR

    host = "0.0.0.0"
    port = 3456
    pm_dir = None

    # Parse args
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--port" and i + 1 < len(args):
            port = int(args[i + 1])
            i += 2
        elif args[i] == "--pm-dir" and i + 1 < len(args):
            pm_dir = args[i + 1]
            i += 2
        elif args[i].isdigit():
            port = int(args[i])
            i += 1
        else:
            i += 1

    # Set plasmodium directory
    if pm_dir:
        PLASMODIUM_DIR = Path(pm_dir)

    if not PLASMODIUM_DIR.exists():
        print(f"Error: {PLASMODIUM_DIR} not found")
        print("Run from a plasmodium project or use --pm-dir")
        sys.exit(1)

    # Change to script dir so index.html is found
    os.chdir(SCRIPT_DIR)

    server = HTTPServer((host, port), DashboardHandler)
    print(f"Dashboard: http://localhost:{port}")
    print(f"Watching: {PLASMODIUM_DIR.absolute()}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped")
        server.shutdown()


if __name__ == "__main__":
    main()
