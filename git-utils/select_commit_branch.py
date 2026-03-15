#!/usr/bin/env python3
"""Select a commit from the current branch using fzf."""

import sys
import subprocess
from git import Repo
from git_utils import get_branch_base


def select_commit_branch():
    """Select a commit from the current branch using fzf. Returns the commit hash or None."""
    repo = Repo(search_parent_directories=True)

    # Get branch base to scope commits to current branch
    base = get_branch_base(repo)

    if base:
        commits = repo.git.log('--abbrev-commit', '--pretty=format:%h %s (%ci)', f'{base}..')
    else:
        # Fallback: show all commits when nothing was selected
        commits = repo.git.log('--abbrev-commit', '--pretty=format:%h %s (%ci)')

    if not commits:
        return None

    # Use fzf to select a commit
    try:
        proc = subprocess.Popen(
            ['fzf', '--height=40%', '--border', '--ansi',
             '--preview', 'echo {} | cut -d" " -f1 | xargs git show --color=always --stat'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=None,  # Let stderr go to terminal
            text=True
        )

        output, _ = proc.communicate(input=commits)

        if proc.returncode == 0 and output:
            commit_hash = output.strip().split(' ')[0]
            return commit_hash
    except FileNotFoundError:
        print("Error: fzf not found. Please install fzf.", file=sys.stderr)
        return None

    return None


def main():
    commit_hash = select_commit_branch()
    if commit_hash:
        print(commit_hash)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
