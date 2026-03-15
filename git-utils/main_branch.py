#!/usr/bin/env python3
"""Get the main branch name of the current repository."""

import sys
from git import Repo
from git_utils import get_main_ref


def get_main_branch(repo: Repo):
    try:
        main_ref = get_main_ref(repo)
        # Extract just the branch name (without 'origin/')
        return main_ref.name.replace('origin/', '')
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        print("Falling back to 'main' as the default main branch name", file=sys.stderr)
        return "main"


def main():
    try:
        repo = Repo(search_parent_directories=True)
        main_branch = get_main_branch(repo)
        print(main_branch)
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
