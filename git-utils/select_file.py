#!/usr/bin/env python3
"""Select a file using fzf."""

import sys
import subprocess
import os
from pathlib import Path


def select_file():
    """Select a file using fzf. Returns the selected file path or None."""
    # Get all files in current directory recursively
    files = []
    for root, dirs, filenames in os.walk('.'):
        # Skip hidden directories
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for filename in filenames:
            if not filename.startswith('.'):
                filepath = os.path.join(root, filename)
                files.append(filepath)

    if not files:
        return None

    files_str = '\n'.join(files)

    # Use fzf to select a file
    try:
        # Run fzf with proper terminal interaction
        proc = subprocess.Popen(
            ['fzf', '--height=40%', '--border', '--ansi',
             '--preview', 'bat --color=always {} || cat {}'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=None,  # Let stderr go to terminal
            text=True
        )

        output, _ = proc.communicate(input=files_str)

        if proc.returncode == 0 and output:
            return output.strip()
    except FileNotFoundError:
        print("Error: fzf not found. Please install fzf.", file=sys.stderr)
        return None

    return None


def main():
    try:
        selected = select_file()
        if selected:
            print(selected)
            return 0
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
