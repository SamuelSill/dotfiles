#!/usr/bin/env python3
"""Show diff between current branch and its remote counterpart."""

import sys
import subprocess
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get current branch name
        current_branch = repo.active_branch
        branch_name = current_branch.name

        # Check if remote branch exists
        remote_branch = f"origin/{branch_name}"

        try:
            remote_ref = repo.remotes.origin.refs[branch_name]
        except (AttributeError, IndexError):
            print(f"Remote branch {remote_branch} does not exist.", file=sys.stderr)
            return 1

        # Get diff
        result = subprocess.run(['git', 'diff', remote_ref.name], cwd=repo.working_dir)
        if result.returncode != 0:
            return result.returncode

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
