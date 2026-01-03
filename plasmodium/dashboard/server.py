#!/usr/bin/env python3
"""
Plasmodium Dashboard Server

Serves the dashboard and handles spore/worker management.
Run from the project root: python3 .plasmodium/server.py
"""

import http.server
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from urllib.parse import parse_qs

DEFAULT_PORT = 3456
PLASMODIUM_DIR = os.path.dirname(os.path.abspath(__file__))

# Load config to get pm CLI path
def get_pm_cli():
    config_path = os.path.join(PLASMODIUM_DIR, 'config.json')
    if os.path.exists(config_path):
        with open(config_path) as f:
            config = json.load(f)
            return config.get('pm_cli', 'pm')
    return 'pm'

PM_CLI = get_pm_cli()

class PlasmodiumHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PLASMODIUM_DIR, **kwargs)

    def do_POST(self):
        if self.path == '/spore':
            self.handle_create_spore()
        else:
            self.send_error(404, 'Not Found')

    def do_PUT(self):
        # Match /worker/<name>
        match = re.match(r'^/worker/(\w+)$', self.path)
        if match:
            self.handle_update_worker(match.group(1))
        else:
            self.send_error(404, 'Not Found')

    def handle_update_worker(self, name):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, 'Invalid JSON')
            return

        workers_path = os.path.join(PLASMODIUM_DIR, 'workers.json')

        # Read current workers
        try:
            with open(workers_path, 'r') as f:
                workers_data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            workers_data = {"workers": {}}

        if name not in workers_data.get("workers", {}):
            self.send_error(404, f'Worker {name} not found')
            return

        # Update worker status
        now = datetime.now(timezone.utc)
        worker = workers_data["workers"][name]

        if "status" in data:
            worker["status"] = data["status"]
            worker["lastActive"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")

            # Log status change to signals
            signals_path = os.path.join(PLASMODIUM_DIR, 'signals.log')
            timestamp = now.strftime("%Y-%m-%d %H:%M:%S")
            signal = f"[{timestamp}] @{name}: status -> {data['status']}\n"
            with open(signals_path, 'a') as f:
                f.write(signal)

        # Write back
        with open(workers_path, 'w') as f:
            json.dump(workers_data, f, indent=2)
            f.write('\n')

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "updated", "worker": name}).encode())

    def handle_create_spore(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')

        try:
            data = json.loads(body)
            task = data.get('task', '').strip()
        except json.JSONDecodeError:
            self.send_error(400, 'Invalid JSON')
            return

        if not task:
            self.send_error(400, 'Task description required')
            return

        # Find pm script - go up from .plasmodium to project root
        project_root = os.path.dirname(PLASMODIUM_DIR)

        # Use pm new which handles spore creation AND auto-spawns a worker
        try:
            result = subprocess.run(
                [PM_CLI, 'new', task],
                cwd=project_root,
                capture_output=True,
                text=True,
                timeout=30
            )

            # Parse spore ID from output (last line should be the ID)
            output_lines = result.stdout.strip().split('\n')
            spore_id = output_lines[-1] if output_lines else 'unknown'

            self.send_response(201)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "id": spore_id,
                "status": "created",
                "auto_spawned": True
            }).encode())

        except subprocess.TimeoutExpired:
            self.send_error(500, 'Timeout creating spore')
        except Exception as e:
            self.send_error(500, f'Error: {str(e)}')

    def log_message(self, format, *args):
        # Quieter logging
        pass

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    max_attempts = 10

    for attempt in range(max_attempts):
        try:
            httpd = http.server.HTTPServer(('0.0.0.0', port), PlasmodiumHandler)

            # Write port to file for background mode
            port_file = os.path.join(PLASMODIUM_DIR, '.dashboard_port')
            with open(port_file, 'w') as f:
                f.write(str(port))

            print(f"Plasmodium Dashboard: http://localhost:{port}")
            print(f"Serving from: {PLASMODIUM_DIR}")
            print("Press Ctrl+C to stop\n")
            sys.stdout.flush()

            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\nShutting down...")
            finally:
                httpd.server_close()
                if os.path.exists(port_file):
                    os.remove(port_file)
            return
        except OSError as e:
            if e.errno == 48:  # Address already in use
                port += 1
            else:
                raise

    print(f"Could not find open port after {max_attempts} attempts", file=sys.stderr)
    sys.exit(1)

if __name__ == '__main__':
    main()
