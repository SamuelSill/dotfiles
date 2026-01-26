#!/usr/bin/env python3
"""Check if there are local changes in the working directory."""

import sys
import os
from git import Repo


def check_no_local_changes(repo: Repo):
    try:
        print(f"Checking for local changes in {repo.working_dir}...")

        if repo.is_dirty(untracked_files=True):
            repo_name = os.path.basename(repo.working_dir)
            print(f"There are local changes ({repo_name}). Please stash or commit them.", file=sys.stderr)
            return False

        return True
    except Exception as e:
        print(f"Error checking changes: {e}", file=sys.stderr)
        return False


def main():
    try:
        repo = Repo(search_parent_directories=True)
        if check_no_local_changes(repo):
            return 0
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
