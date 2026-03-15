#!/usr/bin/env python3
"""Interactive rebase from merge-base with main branch."""

import sys
import subprocess
from git import Repo
from git_utils import get_branch_base


def main():
    try:
        repo = Repo(search_parent_directories=True)

        base = get_branch_base(repo)
        if not base:
            print("Error: No commit selected", file=sys.stderr)
            return 1

        subprocess.run(['git', 'rebase', '-i', base], check=True)
        return 0
    except subprocess.CalledProcessError as e:
        return e.returncode
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
