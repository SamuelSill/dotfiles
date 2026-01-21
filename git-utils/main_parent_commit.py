#!/usr/bin/env python3
"""Get the merge-base commit between current branch and main branch."""

import sys
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get current branch
        current_branch = repo.active_branch

        # Get main branch
        origin = repo.remotes.origin
        main_ref = origin.refs.HEAD.reference

        # Find merge base
        merge_base = repo.merge_base(current_branch, main_ref)
        if merge_base:
            print(merge_base[0].hexsha)
            return 0
        else:
            print("Error: Could not find merge base", file=sys.stderr)
            return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
