#!/usr/bin/env python3
"""Show git graph for the main branch."""

import sys
import subprocess
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get main branch
        origin = repo.remotes.origin
        main_ref = origin.refs.HEAD.reference
        main_branch = main_ref.name

        # Use git log with custom format
        subprocess.run([
            'git', 'log',
            '--abbrev-commit',
            '--decorate',
            "--format=format:%C(bold blue)%h%C(reset) %C(bold green)%<(12)%ar%C(reset) %C(dim white)%<(17)%an%C(reset) %C(white)%<(61)%s%C(reset) %C(auto)%d%C(reset)",
            main_branch
        ], cwd=repo.working_dir)
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
