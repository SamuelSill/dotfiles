#!/usr/bin/env python3
"""Checkout to an existing local branch using fzf."""

import sys
import subprocess
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get list of local branches
        branches = [head.name for head in repo.heads]

        if not branches:
            print("No local branches found.", file=sys.stderr)
            return 1

        branches_str = '\n'.join(branches)

        # Use fzf to select a branch
        try:
            # Run fzf with proper terminal interaction
            proc = subprocess.Popen(
                ['fzf', '--height=40%', '--border', '--ansi',
                 '--preview', 'git log -n 10 --color=always {}'],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=None,  # Let stderr go to terminal
                text=True
            )

            output, _ = proc.communicate(input=branches_str)

            if proc.returncode == 0 and output:
                branch_name = output.strip()
                # Checkout the branch
                repo.git.checkout(branch_name)
                print(f"Switched to branch '{branch_name}'")
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
