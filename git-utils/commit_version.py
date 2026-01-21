#!/usr/bin/env python3
"""Get the closest version tag of a commit."""

import sys
import argparse
from git import Repo


def main():
    parser = argparse.ArgumentParser(description='Get the closest version tag of a commit.')
    parser.add_argument('commit_hash', help='Commit hash to check')
    args = parser.parse_args()

    commit_hash = args.commit_hash

    try:
        repo = Repo(search_parent_directories=True)

        # Get the commit object
        commit = repo.commit(commit_hash)

        # Find milestone branches containing this commit
        milestone_branches = []
        for ref in repo.remotes.origin.refs:
            if ref.name.startswith('origin/milestone-'):
                # Check if this branch contains the commit
                if repo.is_ancestor(commit, ref.commit):
                    milestone_branches.append(ref.name)

        # Sort and get first milestone branch
        milestone_branches.sort()

        # Build list of branches to check
        branches = ['origin/main']
        if milestone_branches:
            branches.append(milestone_branches[0])

        # Search each branch for the closest future tag
        for branch in branches:
            try:
                branch_ref = repo.refs[branch]

                # Get commits from the specified commit to the branch
                commits = list(repo.iter_commits(f'{commit_hash}..{branch}'))

                # Look for tags in these commits
                for c in commits:
                    # Check if this commit has any tags
                    tags = [tag for tag in repo.tags if tag.commit == c]
                    if tags:
                        # Found a tag, print it
                        print(f"{branch}: {tags[0].name}")
                        break
            except Exception:
                continue

        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
