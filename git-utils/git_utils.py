#!/usr/bin/env python3
"""Git utility functions."""

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
    """Get the merge base between a branch and main, with fallback for shallow clones.

    For shallow/--no-history clones where merge_base may not exist,
    falls back to the root commit of the available history.

    Args:
        repo: The git repository
        branch: The branch to find merge base for (defaults to active branch)
        main_ref: The main branch reference (defaults to get_main_ref result)

    Returns:
        The merge base commit, or the root commit as fallback
    """
    if branch is None:
        branch = repo.active_branch
    if main_ref is None:
        main_ref = get_main_ref(repo)

    merge_base = repo.merge_base(branch, main_ref)
    if merge_base:
        return merge_base[0]

    # Fallback for shallow clones: find the root commit of available history
    # This gives us all available commits on the branch
    root_commit = None
    for commit in repo.iter_commits(branch):
        root_commit = commit
    return root_commit
