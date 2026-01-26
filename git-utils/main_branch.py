#!/usr/bin/env python3
"""Get the main branch name of the current repository."""

import sys
from git import Repo


def get_main_branch(repo: Repo):
    # Get the symbolic reference for origin/HEAD
    origin = repo.remotes.origin
    # The origin HEAD reference points to the main branch
    main_ref = origin.refs.HEAD.reference
    # Extract just the branch name (without 'origin/')
    return main_ref.name.replace('origin/', '')


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
