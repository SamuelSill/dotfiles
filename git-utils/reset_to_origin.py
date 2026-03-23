#!/usr/bin/env python3
"""Reset the current branch to its remote counterpart."""

import sys
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        current_branch = repo.active_branch
        branch_name = current_branch.name

        remote_branch = f"origin/{branch_name}"

        try:
            remote_ref = repo.remotes.origin.refs[branch_name]
        except (AttributeError, IndexError):
            print(f"Remote branch {remote_branch} does not exist.", file=sys.stderr)
            return 1

        repo.head.reset(remote_ref.commit, index=True, working_tree=True)
        print(f"Reset to {remote_branch} ({remote_ref.commit.hexsha[:7]})")

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
