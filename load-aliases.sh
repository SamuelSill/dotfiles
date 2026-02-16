#!/bin/sh

# Get the directory where this script is located (POSIX compatible)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

eval "$(python3 "$SCRIPT_DIR/load_aliases.py" sh "$SCRIPT_DIR/aliases.json")"
