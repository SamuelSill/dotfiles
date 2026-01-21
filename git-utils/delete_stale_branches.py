#!/usr/bin/env python3
"""Delete stale branches (merged, in sync with remote, or ending with _old)."""

import sys
from git import Repo


def main():
    try:
        repo = Repo(search_parent_directories=True)

        # Get main branch
        origin = repo.remotes.origin
        main_ref = origin.refs.HEAD.reference
        main_branch_name = main_ref.name.replace('origin/', '')

        # Get current branch
        current_branch = repo.active_branch.name

        # Track branches to delete
        branches_to_delete = set()

        print("Scanning for stale branches...")
        print("")
        print("Already merged branches to delete:")

        # Find merged branches
        for branch in repo.heads:
            if branch.name in [main_branch_name, 'master', current_branch]:
                continue

            # Check if branch is merged into main
            if repo.is_ancestor(branch.commit, main_ref.commit):
                branches_to_delete.add(branch.name)
                print(f"  {branch.name}")

        # Check for branches merged via rebase (cherry-pick equivalent)
        for branch in repo.heads:
            if branch.name in [main_branch_name, 'master', current_branch]:
                continue
            if branch.name in branches_to_delete:
                continue

            # Get commits in branch but not in main
            commits_not_in_main = list(repo.iter_commits(f'{main_ref.commit.hexsha}...{branch.commit.hexsha}',
                                                          ancestry_path=False,
                                                          right_only=True))

            if len(commits_not_in_main) == 0:
                branches_to_delete.add(branch.name)
                print(f"  {branch.name}")

        print("")
        print("Branches not diverged from remote to delete:")

        # Check branches in sync with remote
        for branch in repo.heads:
            if branch.name in [main_branch_name, 'master', current_branch]:
                continue
            if branch.name in branches_to_delete:
                continue

            # Check if remote branch exists
            try:
                remote_branch = origin.refs[branch.name]

                # Check if local has diverged from remote
                diverged_commits = list(repo.iter_commits(f'{remote_branch.commit.hexsha}..{branch.commit.hexsha}'))

                if len(diverged_commits) == 0:
                    branches_to_delete.add(branch.name)
                    print(f"  {branch.name}")
            except (AttributeError, IndexError):
                # Remote branch doesn't exist
                pass

        print("")
        print("Branches ending with _old to delete:")

        # Find branches ending with _old
        for branch in repo.heads:
            if branch.name == current_branch:
                continue
            if branch.name.endswith('_old') and branch.name not in branches_to_delete:
                branches_to_delete.add(branch.name)
                print(f"  {branch.name}")

        if not branches_to_delete:
            print("No stale branches to delete.")
            return 0

        print("")
        print("Branches remaining after deletion:")
        for branch in repo.heads:
            if branch.name not in branches_to_delete:
                marker = "* " if branch.name == current_branch else "  "
                print(f"{marker}{branch.name}")
        print("")

        # Ask for confirmation
        response = input("Delete these branches? (y/N): ")
        if response.lower() == 'y':
            for branch_name in branches_to_delete:
                branch = repo.heads[branch_name]
                repo.delete_head(branch, force=True)
            print("Stale branches deleted successfully.")
        else:
            print("Aborted.")

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
