#!/bin/sh

# Get the directory where this script is located
# Works when sourced from bash or zsh
# Use DOTFILES_DIR to avoid conflicts with other scripts using SCRIPT_DIR
if [ -n "$BASH_VERSION" ]; then
    DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    DOTFILES_DIR="${0:A:h}"
else
    DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
export DOTFILES_DIR

eval "$(python3 "$DOTFILES_DIR/load_aliases.py" sh "$DOTFILES_DIR/aliases.json")"
