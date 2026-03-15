#!/usr/bin/env python3
"""Show commits in the current branch (after the merge base with main)."""

import sys
import argparse
import subprocess
from git import Repo
from git_utils import get_branch_base


def main():
    parser = argparse.ArgumentParser(description='Show commits in the current branch (after the merge base with main).')
    parser.add_argument('git_log_args', nargs='*', help='Additional git log arguments')
    args = parser.parse_args()

    try:
        repo = Repo(search_parent_directories=True)

        base = get_branch_base(repo)
        if not base:
            print("Error: No commit selected", file=sys.stderr)
            return 1

        revision_range = f"{base}.."
        if args.git_log_args:
            subprocess.run(['git', 'log', revision_range] + args.git_log_args, cwd=repo.working_dir)
        else:
            subprocess.run(['git', 'log', '--oneline', revision_range], cwd=repo.working_dir)

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
