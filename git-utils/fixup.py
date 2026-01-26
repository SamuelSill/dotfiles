#!/usr/bin/env python3
"""Fixup staged changes into a selected commit in the current branch."""

import sys
from git import Repo
from select_commit_branch import select_commit_branch


def main():
    try:
        # Select a commit from the current branch
        commit_hash = select_commit_branch()

        if not commit_hash:
            return 0

        # Create fixup commit
        repo = Repo(search_parent_directories=True)
        repo.git.execute(['git', 'commit', f'--fixup={commit_hash}'])

        # Rebase with autosquash
        parent_hash = f'{commit_hash}~1'
        repo.git.execute(['git', '-c', 'core.editor=true', 'rebase', '-i', '--autosquash', parent_hash])

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
