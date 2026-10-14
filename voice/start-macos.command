#!/bin/bash
set -e
cd "$(dirname "$0")"
if ! command -v python3 >/dev/null 2>&1; then
    echo "Install Python 3.10 or newer from https://www.python.org/downloads/macos/ and run this again."
    read -r -p "Press Return to close. "
    exit 1
fi
if [ ! -x .venv/bin/python ]; then python3 -m venv .venv; fi
if ! .venv/bin/python -c "import numpy, sounddevice" >/dev/null 2>&1; then
    .venv/bin/python -m pip install -r requirements.txt
fi
exec .venv/bin/python bridge.py
