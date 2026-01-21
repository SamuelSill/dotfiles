#!/usr/bin/env python3
"""Check if there are local changes in the working directory."""

import sys
import os
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Check for any changes (staged, unstaged, untracked)
        if repo.is_dirty(untracked_files=True):
            repo_name = os.path.basename(repo.working_dir)
            print(f"There are local changes ({repo_name}). Please stash or commit them.", file=sys.stderr)
            return 1

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
