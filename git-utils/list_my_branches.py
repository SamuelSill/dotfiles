#!/usr/bin/env python3
"""List branches created by the current user."""

import sys
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get current user name
        user_name = repo.config_reader().get_value('user', 'name')
        user_name = user_name.replace(' ', '_')

        # List local branches starting with user name
        for branch in repo.heads:
            if branch.name.startswith(f"{user_name}/"):
                print(branch.name)

        # List remote branches starting with user name
        origin = repo.remotes.origin
        for ref in origin.refs:
            branch_name = ref.name
            if branch_name.startswith(f"origin/{user_name}/"):
                print(branch_name)

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
