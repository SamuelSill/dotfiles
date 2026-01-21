#!/usr/bin/env python3
"""Select a commit from the current branch using fzf."""

import sys
import subprocess
from git import Repo


def select_commit_branch():
    """Select a commit from the current branch using fzf. Returns the commit hash or None."""
    repo = Repo(search_parent_directories=True)

    # Get current branch
    current_branch = repo.active_branch

    # Get main branch
    origin = repo.remotes.origin
    main_ref = origin.refs.HEAD.reference

    # Find merge base
    merge_base = repo.merge_base(current_branch, main_ref)
    if not merge_base:
        print("Error: Could not find merge base", file=sys.stderr)
        return None

    # Get formatted commit list
    revision_range = f"{merge_base[0].hexsha}.."
    commits = repo.git.log('--abbrev-commit', '--pretty=format:%H %s (%ci)', revision_range)

    if not commits:
        return None

    # Use fzf to select a commit
    try:
        # Run fzf with proper terminal interaction
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
            # Extract just the commit hash (first field)
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
