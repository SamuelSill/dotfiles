#!/usr/bin/env python3
"""Show git graph with different format options."""

import sys
import subprocess
import argparse
from git import Repo


def main():
    parser = argparse.ArgumentParser(description='Show git graph')
    parser.add_argument('--format', choices=['1', '2'], default='1',
                        help='Graph format: 1 (default, single line) or 2 (double line)')
    args = parser.parse_args()

    try:
        repo = Repo(search_parent_directories=True)

        if args.format == '1':
            # graph1 format
            subprocess.run([
                'git', 'log',
                '--graph',
                '--abbrev-commit',
                '--decorate',
                "--format=format:%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)",
                '--all'
            ], cwd=repo.working_dir)
        else:
            # graph2 format
            subprocess.run([
                'git', 'log',
                '--graph',
                '--abbrev-commit',
                '--decorate',
                "--format=format:%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(auto)%d%C(reset)%n          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)"
            ], cwd=repo.working_dir)
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
