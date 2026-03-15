#!/usr/bin/env python3
"""Show commits in the current branch (after the merge base with main)."""

import sys
import argparse
import subprocess
from git import Repo
from git_utils import get_merge_base, select_start_commit


def main():
    parser = argparse.ArgumentParser(description='Show commits in the current branch (after the merge base with main).')
    parser.add_argument('git_log_args', nargs='*', help='Additional git log arguments')
    args = parser.parse_args()

    try:
        repo = Repo(search_parent_directories=True)

        # Get merge base (with fallback to fzf selection)
        merge_base = get_merge_base(repo)
        if not merge_base:
            merge_base = select_start_commit(repo)
        if not merge_base:
            print("Error: No commit selected", file=sys.stderr)
            return 1

        # If additional arguments provided, pass them to git log
        if args.git_log_args:
            # Use git command directly to support all git log options
            revision_range = f"{merge_base.hexsha}.."
            subprocess.run(['git', 'log', revision_range] + args.git_log_args, cwd=repo.working_dir)
        else:
            # Default format
            subprocess.run(['git', 'log', '--oneline', f'{merge_base.hexsha}..'], cwd=repo.working_dir)

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
