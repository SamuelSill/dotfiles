#!/usr/bin/env python3
"""Get the merge-base commit between current branch and main branch."""

import sys
from git import Repo
from git_utils import get_merge_base


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get merge base (with fallback for shallow clones)
        merge_base = get_merge_base(repo)
        if merge_base:
            print(merge_base.hexsha)
            return 0
        else:
            print("Error: Could not find merge base or root commit", file=sys.stderr)
            return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
