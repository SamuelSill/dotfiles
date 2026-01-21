#!/usr/bin/env python3
"""Show commits in the current branch (after the merge base with main)."""

import sys
import argparse
import subprocess
from git import Repo


def main():
    parser = argparse.ArgumentParser(description='Show commits in the current branch (after the merge base with main).')
    parser.add_argument('git_log_args', nargs='*', help='Additional git log arguments')
    args = parser.parse_args()

    try:
        repo = Repo(search_parent_directories=True)

        # Get current branch
        current_branch = repo.active_branch

        # Get main branch
        origin = repo.remotes.origin
        main_ref = origin.refs.HEAD.reference

        # Find merge base
        merge_base = repo.merge_base(current_branch, main_ref)
        if not merge_base:
            print("Error: Could not find merge base", file=sys.stderr)
            return 1

        # If additional arguments provided, pass them to git log
        if args.git_log_args:
            # Use git command directly to support all git log options
            revision_range = f"{merge_base[0].hexsha}.."
            subprocess.run(['git', 'log', revision_range] + args.git_log_args, cwd=repo.working_dir)
        else:
            # Default format
            subprocess.run(['git', 'log', '--oneline', f'{merge_base[0].hexsha}..'], cwd=repo.working_dir)

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
