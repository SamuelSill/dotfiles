#!/usr/bin/env python3
"""Git utility functions."""

import sys
import subprocess
from typing import Optional
from git import Repo
from git.objects import Commit
from git.refs.reference import Reference


def get_main_ref(repo: Repo) -> Reference:
    """Get the main branch reference from origin.

    Tries to get origin/HEAD, falls back to origin/main for repos
    cloned with --no-history where origin/HEAD may not be set.
    """
    origin = repo.remotes.origin
    try:
        return origin.refs.HEAD.reference
    except (TypeError, AttributeError):
        # Fallback for repos without origin/HEAD (e.g., --no-history clones)
        return origin.refs.main


def get_merge_base(repo: Repo, branch=None, main_ref=None) -> Optional[Commit]:
    """Get the merge base between a branch and main.

    Args:
        repo: The git repository
        branch: The branch to find merge base for (defaults to active branch)
        main_ref: The main branch reference (defaults to get_main_ref result)

    Returns:
        The merge base commit, or None if no common ancestor exists
    """
    if branch is None:
        branch = repo.active_branch
    if main_ref is None:
        main_ref = get_main_ref(repo)

    merge_base = repo.merge_base(branch, main_ref)
    if merge_base:
        return merge_base[0]

    return None


def select_start_commit(repo: Repo) -> Optional[Commit]:
    """Fallback: let the user pick a starting commit via fzf.

    Used when merge-base detection fails (e.g., disconnected histories).
    """
    print("Could not detect branch start automatically. "
          "Please select the starting commit.", file=sys.stderr)

    commits = repo.git.log('--abbrev-commit', '--pretty=format:%H %s (%ci)')
    if not commits:
        return None

    try:
        proc = subprocess.Popen(
            ['fzf', '--height=40%', '--border', '--ansi',
             '--preview', 'echo {} | cut -d" " -f1 | xargs git show --color=always --stat'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=None,
            text=True
        )
        output, _ = proc.communicate(input=commits)

        if proc.returncode == 0 and output:
            commit_hash = output.strip().split(' ')[0]
            return repo.commit(commit_hash)
    except FileNotFoundError:
        print("Error: fzf not found. Please install fzf.", file=sys.stderr)

    return None


def get_branch_base(repo: Repo) -> Optional[str]:
    """Get a revision suitable for use as a range start (excluded from `base..`).

    Returns the merge-base commit hash, or if that fails, asks the user to pick
    the first branch commit via fzf and returns its parent (so the selected commit
    is included in a `base..` range).

    Returns None if nothing was selected. Returns '--root' if the selected commit
    has no parents.
    """
    merge_base = get_merge_base(repo)
    if merge_base:
        return merge_base.hexsha

    selected = select_start_commit(repo)
    if not selected:
        return None

    if selected.parents:
        return selected.parents[0].hexsha
    return '--root'
