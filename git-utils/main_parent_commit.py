#!/usr/bin/env python3
"""Get the merge-base commit between current branch and main branch."""

import sys
from git import Repo
from git_utils import get_branch_base


def main():
    try:
        repo = Repo(search_parent_directories=True)

        base = get_branch_base(repo)
        if base:
            print(base)
            return 0
        else:
            print("Error: No commit selected", file=sys.stderr)
            return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
