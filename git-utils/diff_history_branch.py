#!/usr/bin/env python3
"""Show history of a file in the current branch (with interactive file selection)."""

import sys
import subprocess
from git import Repo
from select_file import select_file
from git_utils import get_merge_base


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get merge base (with fallback for shallow clones)
        merge_base = get_merge_base(repo)
        if not merge_base:
            print("Error: Could not find merge base or root commit", file=sys.stderr)
            return 1

        # Select a file interactively
        selected_file = select_file()

        if not selected_file:
            return 0

        # Show file history in current branch
        subprocess.run(['git', 'log', '-p', f'{merge_base.hexsha}..', '--', selected_file], cwd=repo.working_dir)
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
