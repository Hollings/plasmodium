#!/usr/bin/env python3
"""
Plasmodium Dashboard Server

Serves the dashboard and handles spore/worker management.
Run from the project root: python3 .plasmodium/server.py
"""

import http.server
import json
import os
import hashlib
import re
from datetime import datetime, timezone
from urllib.parse import parse_qs

PORT = 8765
PLASMODIUM_DIR = os.path.dirname(os.path.abspath(__file__))

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

        # Generate spore ID
        now = datetime.now(timezone.utc)
        hash_input = f"{task}{now.isoformat()}"
        spore_id = f"sp-{hashlib.sha256(hash_input.encode()).hexdigest()[:8]}"

        # Create spore entry
        spore = {
            "id": spore_id,
            "parent": None,
            "children": [],
            "status": "raw",
            "phase": None,
            "task": task,
            "claimed_by": None,
            "fruit": None,
            "created": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "creator": "dashboard"
        }

        # Append to spores.jsonl
        spores_path = os.path.join(PLASMODIUM_DIR, 'spores.jsonl')
        with open(spores_path, 'a') as f:
            f.write(json.dumps(spore) + '\n')

        # Log to signals
        signals_path = os.path.join(PLASMODIUM_DIR, 'signals.log')
        timestamp = now.strftime("%Y-%m-%d %H:%M:%S")
        signal = f"[{timestamp}] @dashboard: created spore {spore_id}: {task}\n"
        with open(signals_path, 'a') as f:
            f.write(signal)

        # Respond
        self.send_response(201)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"id": spore_id, "status": "created"}).encode())

    def log_message(self, format, *args):
        # Quieter logging
        pass

def main():
    print(f"Plasmodium Dashboard: http://localhost:{PORT}/dashboard.html")
    print(f"Serving from: {PLASMODIUM_DIR}")
    print("Press Ctrl+C to stop\n")

    with http.server.HTTPServer(('0.0.0.0', PORT), PlasmodiumHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down...")

if __name__ == '__main__':
    main()
