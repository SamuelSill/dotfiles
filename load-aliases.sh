#!/bin/sh

# Get the directory where this script is located
# Works when sourced from bash or zsh
if [ -n "$BASH_VERSION" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    SCRIPT_DIR="${0:A:h}"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

eval "$(python3 "$SCRIPT_DIR/load_aliases.py" sh "$SCRIPT_DIR/aliases.json")"
