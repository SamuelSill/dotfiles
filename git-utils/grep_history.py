#!/usr/bin/env python3
"""Grep for a pattern in git history."""

import sys
import argparse
import subprocess
from git import Repo


def main():
    parser = argparse.ArgumentParser(description='Grep for a pattern in git history.')
    parser.add_argument('pattern', help='Pattern to search for')
    parser.add_argument('--branch', action='store_true', help='Search only in current branch')
    args = parser.parse_args()

    pattern = args.pattern
    branch_only = args.branch

    try:
        repo = Repo(search_parent_directories=True)

        if branch_only:
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

            # Search only in current branch commits
            revision_range = f'{merge_base[0].hexsha}..{current_branch.commit.hexsha}'
        else:
            # Search in all commits
            revision_range = None

        # Use git log with -G to find commits that changed the pattern
        if revision_range:
            subprocess.run(['git', 'log', '--oneline', f'-G{pattern}', revision_range], cwd=repo.working_dir)
        else:
            subprocess.run(['git', 'log', '--oneline', f'-G{pattern}'], cwd=repo.working_dir)

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
