# Get the main branch name of the current repository
alias main-branch-name='git symbolic-ref --short refs/remotes/origin/HEAD'
alias mbn='main-branch-name'

# Shows all commits in the current branch and returns the hash of the selected commit
function select-commit-branch() {
  local commit_hash=$(git log --pretty=format:'%H %s (%ci)' --abbrev-commit $(git merge-base $(git branch --show-current) $(main-branch-name)).. | \
    fzf --height=40% --border --ansi --preview 'echo {} | cut -d" " -f1 | xargs git show --color=always --stat')

  if [[ -n "$commit_hash" ]]; then
    echo "$commit_hash" | cut -d' ' -f1
  fi
}
alias selcb='select-commit-branch'

# Shows all commits in history and returns the hash of the selected commit
function select-commit() {
  local commit_hash=$(git log --pretty=format:'%H %s (%ci)' --abbrev-commit | \
  fzf --height=40% --border --ansi --preview 'echo {} | cut -d" " -f1 | xargs git show --color=always --stat')

  if [[ -n "$commit_hash" ]]; then
    echo "$commit_hash" | cut -d' ' -f1
  fi
}
alias selc='select-commit'

# Shows all files in the current directory and returns the selected file
function select-file() {
  local selected_file=$(find . -type f | fzf --height=40% --border --ansi --preview 'bat --color=always {} || cat {}')

  if [[ -n "$selected_file" ]]; then
    echo "$selected_file"
  fi
}
alias self='select-file'

# Interactive rebase the current branch against the main branch
alias interactive-rebase='git rebase -i $(git merge-base $(git branch --show-current) $(main-branch-name))'
alias ir='interactive-rebase'

# Graph aliases
alias graph1="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)' --all"
alias graph2="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(auto)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)'"
alias graph="graph1"

function graph-main() {
  git log --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) %C(bold green)%<(12)%ar%C(reset) %C(dim white)%<(17)%an%C(reset) %C(white)%<(61)%s%C(reset) %C(auto)%d%C(reset)' $(main-branch-name)
}

# See history of a file
alias diff-history='git log -p -- $(select-file)'
alias dh='diff-history'

# See history of a file in the current branch
alias diff-history-branch='git log -p $(git merge-base $(git branch --show-current) $(main-branch-name)).. -- $(select-file)'
alias dhb='diff-history-branch'

# See commits affecting a file
alias commit-history='git log --oneline -- $(select-file)'
alias ch='commit-history'

# See commits affecting a file in the current branch
alias commit-history-branch='git log --oneline $(git merge-base $(git branch --show-current) $(main-branch-name)).. -- $(select-file)'
alias chb='commit-history-branch'

# Create a temporary commit
alias temp-commit='git commit --no-verify -m "temp"'
alias tc='temp-commit'

# Grep something in the history of the current branch
function _grep_history_branch() {
  git log --oneline -G"$1" $(git merge-base $(git branch --show-current) $(main-branch-name))..
}
alias grep-history-branch='_grep_history_branch'
alias grephb='grep-history-branch'

# Grep something in history
function _grep_history() {
  git log --oneline -G"$1"
}
alias grep-history='_grep_history'
alias greph='grep-history'

# Grep something in a selected commit in the branch
function _grep_commit_branch() {
  local hash=$(select-commit-branch)
  git show $hash | grep -A 5 -B 5 $1
}
alias grep-commit-branch='_grep_commit_branch'
alias grepcb='grep-commit-branch'

# Grep something in a selected commit
function _grep_commit() {
  local hash=$(select-commit)
  git show $hash | grep -A 5 -B 5 $1
}
alias grep-commit='_grep_commit'
alias grepc='grep-commit'

# Fixup staged changes in a selected commit in the current branch
function fixup {
  local hash=$(select-commit-branch)
  git commit --fixup=$hash &&
  git -c core.editor=true rebase -i --autosquash $hash~1
}

# Returns whether there are any local changes in the current directory
function _check-no-local-changes {
  if [[ $(git status --porcelain) ]]; then
    echo "There are local changes ($(basename $(pwd))). Please stash or commit them."
    return 1
  fi

  return 0
}

# Shows a diff between the current branch and its origin
function diff-origin() {
  local branch=$(git rev-parse --abbrev-ref HEAD)
  local remote_branch="origin/$branch"

  if git show-ref --verify --quiet "refs/remotes/$remote_branch"; then
    git diff "$remote_branch"
  else
    echo "Remote branch $remote_branch does not exist."
  fi
}

# Checkout to an existing local branch
function git-checkout() {
  local branch=$(git for-each-ref --format='%(refname:short)' refs/heads/ | fzf --height=40% --border --ansi --preview 'git log -n 10 --color=always {}')

  if [[ -n "$branch" ]]; then
    git checkout "$branch"
  fi
}

# Gets the closest version tag of a commit in history
function get-commit-version {
    local commit=$(select-commit)

    # Get the first milestone branch (sorted alphanumerically) that contains the commit
    local milestone_branch=$(git branch -r --contains "$commit" --format='%(refname:short)' | \
                             grep -E '^origin/milestone-.*' | sort | head -n1)

    # Define branches: Always include origin/main and the first milestone branch (if found)
    local branches=("origin/main")
    if [[ -n "$milestone_branch" ]]; then
        branches+=("$milestone_branch")
    fi

    # Search each branch for the closest future tag
    for branch in "${branches[@]}"; do
        local tag=$(git rev-list --ancestry-path "$commit"..$branch --format="%D" --reverse | \
                    grep -o 'tag: [^,)]*' | head -n1 | cut -d' ' -f2)

        if [[ -n "$tag" ]]; then
            echo "$branch: $tag"
        fi
    done
}
alias gcv='get-commit-version'

# Delete all local branches that have been merged to main, or are in sync with their remote counterpart,
# or that end with _old.
function delete-stale-branches() {
  local main_branch=$(main-branch-name | sed 's/origin\///')

  # Get current branch to avoid deleting it
  local current_branch=$(git branch --show-current)

  # Set to store branches to delete
  declare -A branches_to_delete

  echo "Scanning for stale branches..."
  echo ""
  echo "Already merged branches to delete:"

  # Get list of merged branches (works with fast-forward merges)
  local merged_branches=$(git branch --merged "$main_branch" | \
    grep -v "\*" | \
    grep -v "^\s*${main_branch}$" | \
    grep -v "^\s*master$" | \
    grep -v "^\s*${current_branch}$" | \
    sed 's/^[ \t]*//')

  for branch in $(echo "$merged_branches"); do
    branches_to_delete[$branch]=1
    echo "  $branch"
  done

  # Check for branches merged via rebase (cherry-pick equivalent commits)
  for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
    # Skip main, current branch, and already identified branches
    if [[ "$branch" == "$main_branch" || "$branch" == "$current_branch" || -n "${branches_to_delete[$branch]}" ]]; then
      continue
    fi

    # Check if the branch has any commits not in main
    local commits_not_in_main=$(git log --cherry-pick --right-only --oneline "$main_branch...$branch" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$commits_not_in_main" == "0" ]]; then
      # All commits from this branch have equivalent commits in main (rebased/cherry-picked)
      branches_to_delete[$branch]=1
      echo "  $branch"
    fi
  done

  echo ""
  echo "Branches not diverged from remote to delete:"

  # Get branches that are not diverged from their remote counterpart
  # (either in sync or behind remote)
  for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
    # Skip main, current branch, and already identified branches
    if [[ "$branch" == "$main_branch" || "$branch" == "$current_branch" || -n "${branches_to_delete[$branch]}" ]]; then
      continue
    fi

    # Only check branches that have a remote
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      # Check if local has diverged from remote (has commits not in remote)
      local diverged_commits=$(git rev-list "origin/$branch..$branch" --count 2>/dev/null)
      if [[ "$diverged_commits" == "0" ]]; then
        branches_to_delete[$branch]=1
        echo "  $branch"
      fi
    fi
  done

  echo ""
  echo "Branches ending with _old to delete:"

  local old_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ | \
    grep "_old$" | \
    grep -v "^\s*${current_branch}$")

  for branch in $(echo "$old_branches"); do
    if [[ -z "${branches_to_delete[$branch]}" ]]; then
      branches_to_delete[$branch]=1
      echo "  $branch"
    fi
  done

  if [[ ${#branches_to_delete[@]} -eq 0 ]]; then
    echo "No stale branches to delete."
    return 0
  fi

  echo ""
  echo "Branches remaining after deletion:"
  git branch | grep -v -F -f <(printf '%s\n' "${(@k)branches_to_delete}")
  echo ""

  read "confirm?Delete these branches? (y/N): "

  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    printf '%s\n' "${(@k)branches_to_delete}" | xargs -n 1 git branch -D
    echo "Stale branches deleted successfully."
  else
    echo "Aborted."
  fi
}

function list-my-branches() {
  local current_user="$(git config user.name | tr ' ' '_')"
  git for-each-ref --format='%(refname:short)' refs/heads/ | \
    grep "^$current_user/"
  git for-each-ref --format='%(refname:short)' refs/remotes/origin/ | \
    grep "^origin/$current_user/"
}
alias lmb='list-my-branches'
