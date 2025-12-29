#!/bin/bash
# Wrapper for console checker
# Installs puppeteer if needed, then runs the check

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if puppeteer is installed
if ! npm list puppeteer >/dev/null 2>&1; then
    echo "Installing puppeteer..." >&2
    npm install puppeteer --save-dev 2>&1 | tail -1 >&2
fi

node "$SCRIPT_DIR/check-console.js" "$@"
