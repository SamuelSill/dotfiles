#!/usr/bin/env python3
"""Grep for a pattern in a selected commit."""

import sys
import argparse
import subprocess
from git import Repo


def main():
    parser = argparse.ArgumentParser(description='Grep for a pattern in a selected commit.')
    parser.add_argument('pattern', help='Pattern to search for')
    parser.add_argument('--branch', action='store_true', help='Search only in current branch')
    args = parser.parse_args()

    pattern = args.pattern
    branch_only = args.branch

    try:
        repo = Repo(search_parent_directories=True)

        # Select a commit using the appropriate selector
        if branch_only:
            # Select from current branch
            current_branch = repo.active_branch
            origin = repo.remotes.origin
            main_ref = origin.refs.HEAD.reference
            merge_base = repo.merge_base(current_branch, main_ref)

            if not merge_base:
                print("Error: Could not find merge base", file=sys.stderr)
                return 1

            revision_range = f"{merge_base[0].hexsha}.."
            commits = repo.git.log('--abbrev-commit', '--pretty=format:%H %s (%ci)', revision_range)
        else:
            # Select from all commits
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
                commit_hash = output.strip().split(' ')[0]

                # Show the commit and grep for the pattern
                # Use git show piped to grep for pattern matching with context
                try:
                    # Try using grep command
                    git_show = subprocess.Popen(
                        ['git', 'show', commit_hash],
                        stdout=subprocess.PIPE,
                        cwd=repo.working_dir
                    )
                    subprocess.run(
                        ['grep', '-A', '5', '-B', '5', '--color=always', pattern],
                        stdin=git_show.stdout
                    )
                    git_show.wait()
                except FileNotFoundError:
                    # Fallback: show full commit if grep not available
                    subprocess.run(['git', 'show', commit_hash], cwd=repo.working_dir)

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
