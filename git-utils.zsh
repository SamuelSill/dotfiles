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
alias grephb='grep-history'

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
