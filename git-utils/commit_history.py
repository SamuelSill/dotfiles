#!/usr/bin/env python3
"""Show commits affecting a file (with interactive file selection)."""

import sys
import subprocess
from git import Repo
from select_file import select_file


def main():
    try:
        # Select a file interactively
        selected_file = select_file()

        if not selected_file:
            return 0

        # Show commits affecting the file
        repo = Repo(search_parent_directories=True)
        subprocess.run(['git', 'log', '--oneline', '--', selected_file], cwd=repo.working_dir)
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
