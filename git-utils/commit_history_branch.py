#!/usr/bin/env python3
"""Show commits affecting a file in the current branch (with interactive file selection)."""

import sys
import subprocess
from git import Repo
from select_file import select_file
from git_utils import get_branch_base


def main():
    try:
        repo = Repo(search_parent_directories=True)

        base = get_branch_base(repo)
        if not base:
            print("Error: No commit selected", file=sys.stderr)
            return 1

        selected_file = select_file()
        if not selected_file:
            return 0

        subprocess.run(['git', 'log', '--oneline', f'{base}..', '--', selected_file], cwd=repo.working_dir)
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
