#!/usr/bin/env python3
"""Select a commit from all history using fzf."""

import sys
import subprocess
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get formatted commit list
        commits = repo.git.log('--abbrev-commit', '--pretty=format:%H %s (%ci)')

        if not commits:
            return 0

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
                print(commit_hash)
                return 0
        except FileNotFoundError:
            print("Error: fzf not found. Please install fzf.", file=sys.stderr)
            return 1

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
