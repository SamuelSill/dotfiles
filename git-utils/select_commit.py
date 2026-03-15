#!/usr/bin/env python3
"""Select a commit from all history using fzf."""

import sys
import subprocess
from git import Repo


def select_commit():
    """Select a commit from all history using fzf. Returns the commit hash or None."""
    repo = Repo(search_parent_directories=True)

    # Get formatted commit list
    commits = repo.git.log('--abbrev-commit', '--pretty=format:%h %s (%ci)')

    if not commits:
        return None

    # Use fzf to select a commit
    try:
        # Run fzf with proper terminal interaction
        proc = subprocess.Popen(
            ['fzf', '--height=40%', '--border', '--ansi', '--tiebreak=index',
             '--preview', 'echo {} | cut -d" " -f1 | xargs git show --color=always --stat'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=None,  # Let stderr go to terminal
            text=True
        )

        output, _ = proc.communicate(input=commits)

        if proc.returncode == 0 and output:
            # Extract just the commit hash (first field)
            commit_hash = output.strip().split(' ')[0]
            return commit_hash
    except FileNotFoundError:
        print("Error: fzf not found. Please install fzf.", file=sys.stderr)
        return None

    return None


def main():
    try:
        commit_hash = select_commit()
        if commit_hash:
            print(commit_hash)
            return 0
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
